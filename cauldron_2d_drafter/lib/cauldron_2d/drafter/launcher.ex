defmodule Cauldron2D.Drafter.Launcher do
  @moduledoc """
  A setup page shown before a game starts. The player picks where the game's data is,
  how it is drawn, and anything else the game asks. Play saves the choices, and later
  runs start straight away with them.

      fields = [
        %{key: :dir, label: "Quake folder", kind: {:path, &MyGame.check_dir/1}, discover: &MyGame.find_dir/0},
        %{key: :skill, label: "Skill", kind: {:choice, [{0, "easy"}, {1, "normal"}, {2, "hard"}]}, default: 1},
        Cauldron2D.Drafter.Launcher.drawing_field()
      ]

      case Cauldron2D.Drafter.Launcher.choose(MyGame.Client, fields, overrides: %{skill: 2}, player: "ranger") do
        {:ok, values} -> start_the_game(values)
        :quit -> :ok
      end

  A field is a map:

    * `:key` — the atom its value is kept under
    * `:label` — the text shown beside it
    * `:kind` — `{:path, check}`, a path the player types, where `check` takes it and
      answers `:ok` or `{:error, text}`; `{:choice, [{value, text}]}`, one of a list the
      player steps through; or `:text`, any text
    * `:default` — the value when nothing else gives one (optional)
    * `:discover` — a function answering a value or `nil`, tried when nothing is saved
      (optional; for finding a game's data in the usual places)
    * `:hint` — a line shown under the field (optional)

  `choose/3` works out each value from the run's overrides (from command-line flags),
  then what was saved, then `:discover`, then `:default`. It shows the page when nothing
  has been saved yet, when a path does not pass its check, or when the option
  `launcher: true` asks for it. Play saves the values under
  `$XDG_CONFIG_HOME/<game>/launcher.config` (or `~/.config`), `<game>` named as
  `Cauldron2D.Drafter.Client.Settings` names it. Overrides that skip the page are not
  saved.

  A field with key `:drawing` (`drawing_field/0`) is also written into the player's
  settings (`Cauldron2D.Drafter.Client.Settings`'s `drawing`) when `:player` is given, so
  the page and the game's own options change the same setting.

  On the page, ↑ and ↓ move, ← and → change a choice, Enter edits a path or text or presses
  Play or Quit, and Escape quits.
  """

  use Drafter.App

  alias Cauldron2D.Drafter.Client.Settings

  @type field :: %{
          required(:key) => atom(),
          required(:label) => String.t(),
          required(:kind) =>
            {:path, (String.t() -> :ok | {:error, String.t()})}
            | {:choice, [{term(), String.t()}]}
            | :text,
          optional(:default) => term(),
          optional(:discover) => (-> term() | nil),
          optional(:hint) => String.t()
        }

  @doc "The field for how the game is drawn: automatically, in software, or on the graphics card in the terminal or a window."
  @spec drawing_field() :: field()
  def drawing_field do
    %{
      key: :drawing,
      label: "Drawing",
      kind:
        {:choice,
         [
           {:auto, "graphics card if there is one"},
           {:software, "software only"},
           {:pane, "graphics card, in the terminal"},
           {:window, "graphics card, in a window"}
         ]},
      default: :auto
    }
  end

  @doc """
  The values for `game`'s `fields`, showing the page when it is needed. Options:
  `:overrides` (a map of values for this run), `:launcher` (`true` shows the page
  whatever was saved), `:player` (the player whose settings get the `:drawing` field),
  `:title` (the page's heading, default the game's title).
  """
  @spec choose(module(), [field()], keyword()) :: {:ok, map()} | :quit
  def choose(game, fields, opts \\ []) do
    saved = load(game)
    values = values(fields, Keyword.get(opts, :overrides, %{}), saved)

    if Keyword.get(opts, :launcher, false) or saved == %{} or
         not Enum.all?(fields, &valid?(&1, values)) do
      title = Keyword.get(opts, :title, game.title().name)

      with {:ok, chosen} <- show(title, fields, values) do
        save(game, chosen)
        put_drawing(game, Keyword.get(opts, :player), chosen)
        {:ok, chosen}
      end
    else
      {:ok, values}
    end
  end

  @doc """
  The folders where Steam keeps the game folder `name` on this machine, the ones that
  exist: Steam's own libraries on macOS, Linux (including Flatpak) and Windows, and
  Steam in CrossOver bottles on macOS. For a field's `:discover`.

      Cauldron2D.Drafter.Launcher.steam_folders("Half-Life")
  """
  @spec steam_folders(String.t()) :: [Path.t()]
  def steam_folders(name) do
    home = System.user_home!()

    libraries =
      [
        Path.join(home, "Library/Application Support/Steam/steamapps/common"),
        Path.join(home, ".steam/steam/steamapps/common"),
        Path.join(home, ".local/share/Steam/steamapps/common"),
        Path.join(home, ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common"),
        "C:/Program Files (x86)/Steam/steamapps/common",
        "C:/Program Files/Steam/steamapps/common"
      ] ++
        Path.wildcard(
          Path.join(
            home,
            "Library/Application Support/CrossOver/Bottles/*/drive_c/Program Files (x86)/Steam/steamapps/common"
          )
        )

    for library <- libraries, folder = Path.join(library, name), File.dir?(folder), do: folder
  end

  @doc "The values saved for `game`, or an empty map."
  @spec load(module()) :: map()
  def load(game) do
    case File.read(path(game)) do
      {:ok, binary} -> :erlang.binary_to_term(binary)
      {:error, _reason} -> %{}
    end
  end

  @doc "Saves `values` for `game`."
  @spec save(module(), map()) :: :ok
  def save(game, values) do
    file = path(game)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, :erlang.term_to_binary(values))
  end

  @doc "Where `game`'s launcher choices are kept."
  @spec path(module()) :: Path.t()
  def path(game),
    do: Path.join(Path.dirname(Settings.path(game, "launcher")), "launcher.config")

  @doc "Shows the page with `values` filled in; answers the values on Play, or `:quit`."
  @spec show(String.t(), [field()], map()) :: {:ok, map()} | :quit
  def show(title, fields, values) do
    Drafter.run(__MODULE__,
      props: %{title: title, fields: fields, values: values, reply: self()},
      halt_on_exit: false
    )

    receive do
      {__MODULE__, result} -> result
    after
      0 -> :quit
    end
  end

  @impl true
  def mount(props) do
    %{
      title: props.title,
      fields: props.fields,
      values: props.values,
      reply: props.reply,
      selected: 0,
      editing: nil,
      edit_text: "",
      errors: errors(props.fields, props.values)
    }
  end

  @impl true
  def render(state) do
    rows =
      state.fields
      |> Enum.with_index()
      |> Enum.flat_map(fn {field, index} -> field_rows(field, index, state) end)

    vertical(
      [label(state.title <> " — setup", style: %{fg: :yellow, bold: true}), label("")] ++
        rows ++
        [label("") | button_rows(state)] ++ [label(""), help(state)],
      gap: 0
    )
  end

  @impl true
  def handle_event(:edit_submit, text, state), do: {:ok, finish_edit(state, String.trim(text))}
  def handle_event(_name, _data, state), do: {:noreply, state}

  @impl true
  def handle_event({:key, :escape}, %{editing: key} = state) when key != nil do
    Drafter.blur(:launcher_edit)
    {:ok, %{state | editing: nil}}
  end

  def handle_event({:key, :escape}, state), do: finish(state, :quit)
  def handle_event({:key, :q, [:ctrl]}, state), do: finish(state, :quit)
  def handle_event({:key, :c, [:ctrl]}, state), do: finish(state, :quit)
  def handle_event(_event, %{editing: key} = state) when key != nil, do: {:noreply, state}
  def handle_event({:key, :up}, state), do: {:ok, move(state, -1)}
  def handle_event({:key, :down}, state), do: {:ok, move(state, 1)}
  def handle_event({:key, :left}, state), do: {:ok, step(state, -1)}
  def handle_event({:key, :right}, state), do: {:ok, step(state, 1)}
  def handle_event({:key, :enter}, state), do: press(state)
  def handle_event(_event, state), do: {:noreply, state}

  defp values(fields, overrides, saved) do
    Map.new(fields, fn field ->
      value =
        Map.get(overrides, field.key) || Map.get(saved, field.key) || discovered(field, saved) ||
          Map.get(field, :default)

      {field.key, value}
    end)
  end

  defp discovered(field, saved) when saved == %{}, do: discover(field)

  defp discovered(field, saved),
    do: if(Map.has_key?(saved, field.key), do: nil, else: discover(field))

  defp discover(%{discover: discover}), do: discover.()
  defp discover(_field), do: nil

  defp valid?(%{kind: {:path, check}} = field, values),
    do: checked(check, values[field.key]) == :ok

  defp valid?(_field, _values), do: true

  defp checked(_check, nil), do: {:error, "not set"}
  defp checked(_check, ""), do: {:error, "not set"}
  defp checked(check, path), do: check.(Path.expand(path))

  defp errors(fields, values) do
    for %{kind: {:path, check}} = field <- fields,
        {:error, text} <- [checked(check, values[field.key])],
        into: %{},
        do: {field.key, text}
  end

  defp put_drawing(_game, nil, _values), do: :ok

  defp put_drawing(game, player, %{drawing: drawing}) do
    settings = Settings.load(game, player)
    Settings.save(%{settings | drawing: drawing}, game, player)
  end

  defp put_drawing(_game, _player, _values), do: :ok

  defp field_rows(field, index, state) do
    selected? = index == state.selected
    marker = if selected?, do: "▶ ", else: "  "
    style = if selected?, do: %{fg: :cyan, bold: true}, else: %{}

    main =
      if state.editing == field.key,
        do:
          horizontal(
            [
              label(marker <> pad(field.label)),
              text_input(
                id: :launcher_edit,
                bind: :edit_text,
                on_submit: :edit_submit,
                placeholder: to_string(state.values[field.key] || ""),
                flex: 1
              )
            ],
            gap: 0
          ),
        else:
          label(marker <> pad(field.label) <> shown(field, state.values[field.key]), style: style)

    [main] ++ error_row(state.errors[field.key]) ++ hint_row(field)
  end

  defp error_row(nil), do: []
  defp error_row(text), do: [label("    " <> text, style: %{fg: :red})]

  defp hint_row(%{hint: hint}), do: [label("    " <> hint, style: %{fg: :bright_black})]
  defp hint_row(_field), do: []

  defp pad(text), do: String.pad_trailing(text, 18)

  defp shown(%{kind: {:choice, choices}}, value),
    do: "◀ " <> (choices |> List.keyfind(value, 0, {value, inspect(value)}) |> elem(1)) <> " ▶"

  defp shown(_field, nil), do: "(not set — Enter to type it)"
  defp shown(_field, ""), do: "(not set — Enter to type it)"
  defp shown(_field, value), do: to_string(value)

  defp button_rows(state) do
    count = length(state.fields)

    [
      button_row("Play", state.selected == count, :green),
      button_row("Quit", state.selected == count + 1, :red)
    ]
  end

  defp button_row(text, true, colour),
    do: label("▶ [ #{text} ]", style: %{fg: colour, bold: true})

  defp button_row(text, false, _colour), do: label("  [ #{text} ]")

  defp help(%{editing: key}) when key != nil,
    do: label("Type the path, Enter to keep it, Esc to cancel", style: %{fg: :bright_black})

  defp help(_state),
    do:
      label("↑ ↓ move     ← → change     Enter edit or press     Esc quit",
        style: %{fg: :bright_black}
      )

  defp move(state, delta) do
    rows = length(state.fields) + 2
    %{state | selected: Integer.mod(state.selected + delta, rows)}
  end

  defp step(state, delta) do
    case Enum.at(state.fields, state.selected) do
      %{kind: {:choice, choices}, key: key} ->
        values = Enum.map(choices, &elem(&1, 0))
        index = Enum.find_index(values, &(&1 == state.values[key])) || 0
        value = Enum.at(values, Integer.mod(index + delta, length(values)))
        %{state | values: Map.put(state.values, key, value)}

      _other ->
        state
    end
  end

  defp press(state) do
    count = length(state.fields)

    cond do
      state.selected == count -> play(state)
      state.selected == count + 1 -> finish(state, :quit)
      true -> {:ok, enter_field(state, Enum.at(state.fields, state.selected))}
    end
  end

  defp enter_field(state, %{kind: {:choice, _choices}}), do: step(state, 1)

  defp enter_field(state, field) do
    Drafter.focus(:launcher_edit)
    %{state | editing: field.key, edit_text: ""}
  end

  defp finish_edit(state, "") do
    Drafter.blur(:launcher_edit)
    %{state | editing: nil}
  end

  defp finish_edit(%{editing: key} = state, text) do
    Drafter.blur(:launcher_edit)
    field = Enum.find(state.fields, &(&1.key == key))
    values = Map.put(state.values, key, text)
    errors = Map.merge(Map.delete(state.errors, key), errors([field], values))
    %{state | editing: nil, values: values, errors: errors}
  end

  defp play(state) do
    errors = errors(state.fields, state.values)

    if errors == %{},
      do: finish(state, {:ok, expanded(state)}),
      else: {:ok, %{state | errors: errors, selected: first_error(state.fields, errors)}}
  end

  defp expanded(state) do
    Map.new(state.values, fn {key, value} ->
      case Enum.find(state.fields, &(&1.key == key)) do
        %{kind: {:path, _check}} when is_binary(value) -> {key, Path.expand(value)}
        _other -> {key, value}
      end
    end)
  end

  defp first_error(fields, errors),
    do: Enum.find_index(fields, &Map.has_key?(errors, &1.key)) || 0

  defp finish(state, result) do
    send(state.reply, {__MODULE__, result})
    {:stop, :normal}
  end
end
