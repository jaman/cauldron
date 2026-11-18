defmodule Cauldron2D.Native.Settings do
  @moduledoc """
  A player's settings on a phone: the effects and music levels, the key preset, the hand
  the on-screen controls are laid out for, whether their buttons move and where they were
  left, and the game's own options, kept under
  `Cauldron.Paths.config(home, "<player>.mobile.settings")`, `home` the game's
  `Cauldron.Client.Game.home/1`.
  """

  alias Cauldron.{Audio, Paths}
  alias Cauldron.Client.{Game, Stage}
  alias Cauldron.Menu.Item

  @doc "The settings saved for `player`, over the defaults."
  @spec load(module(), String.t()) :: map()
  def load(game, player) do
    defaults =
      Map.merge(Audio.default_levels(), %{
        preset: game.keymaps() |> Enum.map(&elem(&1, 0)) |> List.first(),
        pointer: false
      })

    Stage.with_options(game, Map.merge(defaults, saved(game, player)))
  end

  @doc """
  The rows a game's options page shows for the phone's own settings, `text` given each
  row's words to set them in the game's style: the hand the controls are laid out for
  (`:hand`, `:right` or `:left`), and whether the buttons stay put or move to the thumb
  (`:buttons`, `:locked` or `:move`), as `Cauldron2D.Native.Pad` takes them.

      items = game_rows ++ Cauldron2D.Native.Settings.menu_items(&String.upcase/1)
  """
  @spec menu_items((String.t() -> String.t())) :: [Item.t()]
  def menu_items(text \\ & &1),
    do: [
      Item.choice(text.("Hand"), [:hand], [{:right, text.("right")}, {:left, text.("left")}]),
      Item.choice(text.("Buttons"), [:buttons], [
        {:locked, text.("locked")},
        {:move, text.("move")}
      ])
    ]

  @doc "The hand the controls are laid out for."
  @spec hand(map()) :: :right | :left
  def hand(%{hand: :left}), do: :left
  def hand(_settings), do: :right

  @doc "Whether the buttons stay put (`:locked`, the default) or move to the thumb."
  @spec buttons(map()) :: :locked | :move
  def buttons(%{buttons: :move}), do: :move
  def buttons(_settings), do: :locked

  @doc "Where the button fan was left, as `Cauldron2D.Native.Pad.offset/1` gives it."
  @spec fan_offset(map()) :: {number(), number()}
  def fan_offset(%{fan_offset: {inward, up}}) when is_number(inward) and is_number(up),
    do: {inward, up}

  def fan_offset(_settings), do: {0, 0}

  @doc "Keep `settings` for `player`."
  @spec save(module(), String.t(), map()) :: :ok
  def save(game, player, settings) do
    file = path(game, player)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, :erlang.term_to_binary(settings))
  end

  defp saved(game, player) do
    with {:ok, bytes} <- File.read(path(game, player)),
         %{} = saved <- safe_term(bytes) do
      saved
    else
      _missing -> %{}
    end
  end

  defp safe_term(bytes) do
    :erlang.binary_to_term(bytes, [:safe])
  rescue
    ArgumentError -> nil
  end

  defp path(game, player), do: Paths.config(Game.home(game), "#{player}.mobile.settings")
end
