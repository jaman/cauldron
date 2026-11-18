defmodule Cauldron.SFX.Editor do
  @moduledoc """
  The state of a sound-effect editor, with no way of drawing it or playing it.

  A front end holds a `t:t/0`, hands it keys and draws `view/1`:

      state = Cauldron.SFX.Editor.mount(%{bank: Cauldron.SFX.starter()})
      {state, effects} = Cauldron.SFX.Editor.key(state, :p)
      view = Cauldron.SFX.Editor.view(state)

  Anything the front end has to *do* comes back as an effect — `{:play, sound}` for the
  sound to sound, `:quit` to close — so the editor itself touches no device:

    * `Cauldron.SFX.Editor.Drafter` draws it in a terminal and plays through a
      `TuningFork.Stage`
    * a web or notebook front end draws the same `view/1` and sends the same keys, or the
      commands `command/2` names

  Writing the bank is the one thing the editor does itself, because it is a file operation
  either way.

  ## Keys

  | Key | Command |
  | --- | --- |
  | ↑ ↓ | `{:select, -1}` / `{:select, 1}` |
  | a row | `{:selected, index}` |
  | ← → | `{:variant, -1}` / `{:variant, 1}` |
  | `p` | `:play` |
  | `s` | `:shape` |
  | `+` `-` | `{:gain, 0.05}` / `{:gain, -0.05}` |
  | `>` `<` | `{:pan, 0.1}` / `{:pan, -0.1}` |
  | `]` `[` | `{:pitch, 1}` / `{:pitch, -1}` |
  | `1` `2` | `{:decay, -0.01}` / `{:decay, 0.01}` |
  | `3` `4` | `{:sweep, -0.1}` / `{:sweep, 0.1}` |
  | `5` `6` | `{:cutoff, -0.05}` / `{:cutoff, 0.05}` |
  | `7` `8` | `{:attack, -0.005}` / `{:attack, 0.005}` |
  | `9` `0` | `{:release, -0.01}` / `{:release, 0.01}` |
  | `k` `l` | `{:space, -0.1}` / `{:space, 0.1}` |
  | `t` | `:next_preset` |
  | `a` `d` | `:add_variant` / `:remove_variant` |
  | `x` | `:remove_event` |
  | `w` | `:write` |
  | `q` | `:quit` |
  """

  alias Cauldron.SFX
  alias Cauldron.SFX.Presets

  @typedoc "Something for the front end to do with the result of a key."
  @type effect :: {:play, Cauldron.Audio.sound()} | :quit

  @typedoc """
  The editor's state.

    * `:bank` — the `Cauldron.SFX` being edited
    * `:names` — its event names, in order
    * `:selected` — the event the cursor is on, counted from zero
    * `:variant` — which of its variants is shown, counted from zero
    * `:out` — where `:write` writes
    * `:said` — the message under the recipe
  """
  @type t :: %{
          bank: SFX.t(),
          names: [String.t()],
          selected: non_neg_integer(),
          variant: non_neg_integer(),
          out: Path.t(),
          preset: non_neg_integer(),
          said: String.t()
        }

  @typedoc """
  What a front end draws.

    * `:title` — the editor's title
    * `:summary` — the line above the list
    * `:rows` — one per event: `%{label: text, selected: boolean}`
    * `:detail` — the selected variant's recipe, as a line
    * `:said` — the message under the recipe
    * `:keys` — `{key, what it does}`, for a help line
  """
  @type view :: %{
          title: String.t(),
          summary: String.t(),
          rows: [%{label: String.t(), selected: boolean()}],
          detail: String.t(),
          said: String.t(),
          keys: [{String.t(), String.t()}]
        }

  @keys [
    {"↑↓", "event"},
    {"←→", "variant"},
    {"p", "play"},
    {"s", "shape"},
    {"+/-", "gain"},
    {"</>", "pan"},
    {"[/]", "pitch"},
    {"1/2", "decay"},
    {"3/4", "sweep"},
    {"5/6", "cutoff"},
    {"7/8", "attack"},
    {"9/0", "release"},
    {"k/l", "space"},
    {"t", "preset"},
    {"a/d", "variant"},
    {"n/x", "event"},
    {"w", "write"},
    {"q", "quit"}
  ]

  @doc """
  The state the editor starts in.

  `props` is a map or a keyword list carrying:

    * `:bank` — the `Cauldron.SFX` to edit, default `Cauldron.SFX.starter/0`
    * `:out` — where `:write` writes, default `"sfx.json"`

  Any other key is ignored.
  """
  @spec mount(map() | keyword()) :: t()
  def mount(props) do
    props = Map.new(props)
    bank = Map.get(props, :bank) || SFX.starter()

    %{
      bank: bank,
      names: SFX.events(bank),
      selected: 0,
      variant: 0,
      out: Map.get(props, :out, "sfx.json"),
      preset: 0,
      said: "↑↓ event · ←→ variant · p play · w write · q quit"
    }
  end

  @doc "A key as the command it stands for, or `nil`."
  @spec command(atom()) :: term()
  def command(:up), do: {:select, -1}
  def command(:down), do: {:select, 1}
  def command(:left), do: {:variant, -1}
  def command(:right), do: {:variant, 1}
  def command(:p), do: :play
  def command(:s), do: :shape
  def command(key) when key in [:+, :=], do: {:gain, 0.05}
  def command(key) when key in [:-, :_], do: {:gain, -0.05}
  def command(key) when key in [:>, :.], do: {:pan, 0.1}
  def command(key) when key in [:<, :","], do: {:pan, -0.1}
  def command(:"]"), do: {:pitch, 1}
  def command(:"["), do: {:pitch, -1}
  def command(:"1"), do: {:decay, -0.01}
  def command(:"2"), do: {:decay, 0.01}
  def command(:"3"), do: {:sweep, -0.1}
  def command(:"4"), do: {:sweep, 0.1}
  def command(:"5"), do: {:cutoff, -0.05}
  def command(:"6"), do: {:cutoff, 0.05}
  def command(:"7"), do: {:attack, -0.005}
  def command(:"8"), do: {:attack, 0.005}
  def command(:"9"), do: {:release, -0.01}
  def command(:"0"), do: {:release, 0.01}
  def command(:k), do: {:space, -0.1}
  def command(:l), do: {:space, 0.1}
  def command(:t), do: :next_preset
  def command(:a), do: :add_variant
  def command(:d), do: :remove_variant
  def command(:x), do: :remove_event
  def command(:w), do: :write
  def command(:q), do: :quit
  def command(_anything_else), do: nil

  @doc "A key, as `command/2` reads it and then does it. An unknown key changes nothing."
  @spec key(t(), atom()) :: {t(), [effect()]}
  def key(%{} = state, key) do
    case command(key) do
      nil -> {state, []}
      command -> command(state, command)
    end
  end

  @doc """
  Do a command: `{:select, by}`, `{:variant, by}`, `:play`, `:shape`, `{:gain, by}`,
  `{:pan, by}`, `{:pitch, semitones}`, `:add_variant`, `:remove_variant`, `:write`,
  `:quit`.
  """
  @spec command(t(), term()) :: {t(), [effect()]}
  def command(%{} = state, {:select, by}), do: {move(state, by), []}
  def command(%{} = state, {:selected, index}), do: {selected(state, index), []}
  def command(%{} = state, {:variant, by}), do: {step_variant(state, by), []}
  def command(%{} = state, {:gain, by}), do: {gain(state, by), []}
  def command(%{} = state, {:pan, by}), do: {pan(state, by), []}
  def command(%{} = state, {:pitch, semitones}), do: {pitch(state, semitones), []}
  def command(%{} = state, {:decay, by}), do: {decay(state, by), []}
  def command(%{} = state, {:sweep, by}), do: {sweep(state, by), []}
  def command(%{} = state, {:cutoff, by}), do: {cutoff(state, by), []}
  def command(%{} = state, {:attack, by}), do: {attack(state, by), []}
  def command(%{} = state, {:release, by}), do: {release(state, by), []}
  def command(%{} = state, {:space, by}), do: {space(state, by), []}
  def command(%{} = state, :next_preset), do: {next_preset(state), []}
  def command(%{} = state, {:new_event, name}), do: {new_event(state, name), []}
  def command(%{} = state, :remove_event), do: {remove_event(state), []}
  def command(%{} = state, :play), do: play(state)
  def command(%{} = state, :shape), do: {shape(state), []}
  def command(%{} = state, :add_variant), do: {add_variant(state), []}
  def command(%{} = state, :remove_variant), do: {remove_variant(state), []}
  def command(%{} = state, :write), do: {write(state), []}
  def command(%{} = state, :quit), do: {state, [:quit]}
  def command(%{} = state, _unknown), do: {state, []}

  @doc "What a front end draws."
  @spec view(t()) :: view()
  def view(%{} = state) do
    %{
      title: "SFX",
      summary: summary(state),
      rows: rows(state),
      detail: detail(state),
      said: state.said,
      keys: @keys
    }
  end

  @doc "The event the cursor is on, or `nil`."
  @spec current(t()) :: String.t() | nil
  def current(state), do: Enum.at(state.names, state.selected)

  @doc "The event the cursor is on, as the bank holds it, or `nil`."
  @spec current_event(t()) :: SFX.event() | nil
  def current_event(state) do
    case current(state) do
      nil -> nil
      name -> SFX.event(state.bank, name)
    end
  end

  @doc "The variant shown, or `nil`."
  @spec current_variant(t()) :: SFX.recipe() | nil
  def current_variant(state) do
    case current(state) do
      nil -> nil
      name -> SFX.variant(state.bank, name, state.variant)
    end
  end

  # -- moving ---------------------------------------------------------------

  defp move(state, by), do: selected(state, state.selected + by)

  defp selected(state, index) do
    index = index |> max(0) |> min(max(length(state.names) - 1, 0))

    %{state | selected: index, variant: 0}
  end

  defp step_variant(state, by) do
    case current_event(state) do
      %{variants: variants} when variants != [] ->
        %{state | variant: (state.variant + by) |> max(0) |> min(length(variants) - 1)}

      _none ->
        state
    end
  end

  # -- changing -------------------------------------------------------------

  defp shape(state) do
    case current_variant(state) do
      %{"kind" => "tone", "shape" => shape} ->
        next = shape |> next_shape() |> to_string()
        edit_variant(state, fn recipe -> Map.put(recipe, "shape", next) end, "shape #{next}")

      %{"kind" => "noise"} ->
        %{state | said: "a noise has no shape — it is filtered noise"}

      _layers ->
        %{state | said: "a layered sound is edited part by part — no shape here"}
    end
  end

  defp next_shape(shape) do
    shapes = SFX.shapes()
    index = Enum.find_index(shapes, &(&1 == shape)) || -1
    Enum.at(shapes, rem(index + 1, length(shapes)))
  end

  defp gain(state, by) do
    edit_event(
      state,
      fn event -> %{event | gain: (event.gain + by) |> max(0.0)} end,
      fn event -> "gain #{fmt(event.gain)}" end
    )
  end

  defp pan(state, by) do
    edit_event(
      state,
      fn event -> %{event | pan: (event.pan + by) |> max(-1.0) |> min(1.0)} end,
      fn event -> "pan #{fmt(event.pan)}" end
    )
  end

  defp pitch(state, semitones) do
    case current_variant(state) do
      %{"kind" => "tone"} = recipe ->
        freq = recipe["freq"] * :math.pow(2, semitones / 12)

        edit_variant(
          state,
          fn recipe -> Map.put(recipe, "freq", freq) end,
          "pitch #{fmt(freq)} Hz"
        )

      _other ->
        %{state | said: "only a tone has a pitch"}
    end
  end

  defp decay(state, by) do
    edit_recipe(
      state,
      fn recipe -> %{recipe | "decay" => (recipe["decay"] + by) |> max(0.005)} end,
      fn recipe ->
        "decay #{fmt(recipe["decay"])}s"
      end
    )
  end

  defp sweep(state, by) do
    case current_variant(state) do
      %{"kind" => "tone"} ->
        edit_recipe(
          state,
          fn recipe -> %{recipe | "sweep" => (recipe["sweep"] + by) |> max(0.0)} end,
          fn recipe ->
            "sweep #{fmt(recipe["sweep"])}"
          end
        )

      _other ->
        %{state | said: "only a tone sweeps"}
    end
  end

  defp cutoff(state, by) do
    edit_recipe(
      state,
      fn recipe ->
        current = recipe["cutoff"] || 0.8
        %{recipe | "cutoff" => (current + by) |> max(0.0) |> min(1.0)}
      end,
      fn recipe -> "cutoff #{fmt(recipe["cutoff"])}" end
    )
  end

  defp attack(state, by) do
    edit_recipe(
      state,
      fn recipe -> %{recipe | "attack" => (recipe["attack"] + by) |> max(0.0)} end,
      fn recipe -> "attack #{fmt(recipe["attack"])}s" end
    )
  end

  defp release(state, by) do
    edit_recipe(
      state,
      fn recipe -> %{recipe | "release" => (recipe["release"] + by) |> max(0.0)} end,
      fn recipe -> "release #{fmt(recipe["release"])}s" end
    )
  end

  defp space(state, by) do
    edit_event(
      state,
      fn event -> %{event | space: (event.space + by) |> max(0.0) |> min(1.0)} end,
      fn event -> "space #{fmt(event.space)}" end
    )
  end

  defp next_preset(state) do
    preset = rem(state.preset + 1, length(Presets.names()))
    %{state | preset: preset, said: "new events start as #{Presets.names() |> Enum.at(preset)}"}
  end

  defp new_event(state, name) do
    name = name |> to_string() |> String.trim()

    cond do
      name == "" ->
        %{state | said: "an event needs a name"}

      Map.has_key?(state.bank.events, name) ->
        %{state | said: "#{name} is already an event"}

      true ->
        {_preset, preset} = Presets.get(state.preset)
        bank = SFX.put_event(state.bank, name, %{space: preset.space, variants: [preset.recipe]})
        selected = Enum.find_index(SFX.events(bank), &(&1 == name)) || 0

        %{
          state
          | bank: bank,
            names: SFX.events(bank),
            selected: selected,
            variant: 0,
            said: "added #{name}"
        }
    end
  end

  defp remove_event(state) do
    case current(state) do
      nil ->
        %{state | said: "no event to remove"}

      name ->
        bank = SFX.remove_event(state.bank, name)
        names = SFX.events(bank)

        %{
          state
          | bank: bank,
            names: names,
            selected: min(state.selected, max(length(names) - 1, 0)),
            variant: 0,
            said: "removed #{name}"
        }
    end
  end

  defp add_variant(state) do
    case {current_event(state), current_variant(state)} do
      {%{variants: variants}, %{} = variant} ->
        bank =
          SFX.update_event(state.bank, current(state), fn event ->
            %{event | variants: event.variants ++ [variant]}
          end)

        %{
          state
          | bank: bank,
            variant: length(variants),
            said: "added variant #{length(variants) + 1}"
        }

      _nothing_to_copy ->
        state
    end
  end

  defp remove_variant(state) do
    case current_event(state) do
      %{variants: [_one]} ->
        %{state | said: "an event keeps at least one variant"}

      %{variants: variants} when variants != [] ->
        bank =
          SFX.update_event(state.bank, current(state), fn event ->
            %{event | variants: List.delete_at(event.variants, state.variant)}
          end)

        variant = state.variant |> min(length(variants) - 2) |> max(0)
        %{state | bank: bank, variant: variant, said: "removed a variant"}

      _no_event ->
        state
    end
  end

  # Decay, sweep and cutoff only mean something to a recipe that has them; a layer is edited
  # part by part, so they say so rather than doing nothing silently.
  defp edit_recipe(state, fun, said) do
    case current_variant(state) do
      %{"kind" => kind} = recipe when kind in ["tone", "noise"] ->
        updated = fun.(recipe)
        edit_variant(state, fn _recipe -> updated end, said.(updated))

      _other ->
        %{state | said: "only a tone or a noise has that"}
    end
  end

  defp edit_variant(state, fun, said) do
    case current_variant(state) do
      %{} ->
        bank =
          SFX.update_event(state.bank, current(state), fn event ->
            %{event | variants: List.update_at(event.variants, state.variant, fun)}
          end)

        %{state | bank: bank, said: said}

      _no_variant ->
        state
    end
  end

  defp edit_event(state, fun, said) do
    case current_event(state) do
      %{} ->
        bank = SFX.update_event(state.bank, current(state), fun)
        %{state | bank: bank, said: said.(SFX.event(bank, current(state)))}

      _no_event ->
        state
    end
  end

  defp write(state) do
    case SFX.write(state.bank, state.out) do
      :ok -> %{state | said: "wrote #{state.out}"}
      {:error, reason} -> %{state | said: "could not write #{state.out}: #{inspect(reason)}"}
    end
  end

  # -- playing --------------------------------------------------------------

  defp play(state) do
    name = current(state)

    case SFX.voice(state.bank, name, variant: state.variant) do
      nil ->
        {%{state | said: "#{inspect(name)} is not an event"}, []}

      voice ->
        {%{state | said: "played #{name} — variant #{state.variant + 1}"}, [{:play, voice}]}
    end
  end

  # -- drawing --------------------------------------------------------------

  defp summary(state) do
    count = length(state.names)
    variants = state |> current_event() |> variant_count()

    "#{count} events · variant #{if variants == 0, do: 0, else: state.variant + 1}/#{variants} · " <>
      "new events: #{Enum.at(Presets.names(), state.preset)} · #{state.bank.rate} Hz #{state.bank.channels} ch"
  end

  defp rows(state) do
    state.names
    |> Enum.with_index()
    |> Enum.map(fn {name, index} ->
      %{label: row(name, SFX.event(state.bank, name)), selected: index == state.selected}
    end)
  end

  defp row(name, event) do
    count = variant_count(event)

    "#{String.pad_trailing(name, 14)} #{String.pad_leading("#{count}", 2)} variant" <>
      "#{if count == 1, do: " ", else: "s"}  gain #{fmt(event.gain)}  pan #{fmt(event.pan)}"
  end

  defp variant_count(nil), do: 0
  defp variant_count(%{variants: variants}), do: length(variants)

  defp detail(state) do
    case current_variant(state) do
      nil ->
        "no variant — an event with none makes no sound"

      %{"kind" => "tone"} = recipe ->
        "tone #{recipe["shape"]} #{fmt(recipe["freq"])} Hz · decay #{fmt(recipe["decay"])}s · " <>
          "sweep #{fmt(recipe["sweep"])} · gain #{fmt(recipe["gain"])} · cutoff #{fmt(recipe["cutoff"])}"

      %{"kind" => "noise"} = recipe ->
        "noise · decay #{fmt(recipe["decay"])}s · gain #{fmt(recipe["gain"])} · " <>
          "cutoff #{fmt(recipe["cutoff"])}"

      %{"kind" => "layers", "parts" => parts} ->
        "layers · " <>
          Enum.map_join(parts, " · ", fn part ->
            "#{part["at_ms"]}ms #{part["recipe"]["kind"]}"
          end)
    end
  end

  defp fmt(nil), do: "—"
  defp fmt(value) when is_number(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)
end
