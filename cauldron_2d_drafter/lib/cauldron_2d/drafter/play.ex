defmodule Cauldron2D.Drafter.Play do
  @moduledoc """
  Runs a game's terminal client (`Cauldron2D.Drafter.Client`) from command-line
  arguments: what a game's own mix task, or `mix cauldron.play`, calls.

      defmodule Mix.Tasks.MyGame do
        use Mix.Task

        def run(argv), do: Cauldron2D.Drafter.Play.run(MyGame.Client, argv, name: "player")
      end

  ## Flags

    * `--name NAME` — the player's name
    * `--mute`, `--no-mute` — sound off or on
    * `--picture OPTIONS` — the picture options, as `Cauldron2D.Drafter.Client.Picture`
      reads them (`native,swap`, `window`, …)
    * `--trace FILE` — write `Cauldron.Trace` events to `FILE`

  A flag given becomes the client's mount prop of the same name (`:username` for
  `--name`), so it comes first in `Cauldron.Launch`'s order; a flag left out leaves the
  prop to the game's saved launch values, the environment and the defaults. Arguments
  that are not flags are ignored.

  ## Options

    * `:name` — the player's name when `--name` is not given. Default `"player"`
    * `:props` — more mount props, the game's own; the flags are put over them
    * `:before` — a function of no arguments run once the application has started and
      before the client opens, such as registering the game's worlds
    * `:refresh_rate` — the client's first refresh rate, as `Drafter.run/2` takes it
  """

  @flags [name: :string, mute: :boolean, picture: :string, trace: :string]

  @doc "Starts the application and runs `game`'s terminal client with `argv`'s flags; returns when the player quits."
  @spec run(module(), [String.t()], keyword()) :: :ok
  def run(game, argv, opts \\ []) do
    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    if before = Keyword.get(opts, :before), do: before.()

    Drafter.run(
      Cauldron2D.Drafter.Client,
      Keyword.take(opts, [:refresh_rate]) ++ [props: props(game, argv, opts)]
    )
  end

  @doc "The client's mount props for `game` given `argv`'s flags and `run/3`'s options."
  @spec props(module(), [String.t()], keyword()) :: map()
  def props(game, argv, opts \\ []) do
    {flags, _rest, _invalid} = OptionParser.parse(argv, strict: @flags)

    opts
    |> Keyword.get(:props, %{})
    |> Map.merge(%{game: game, username: Keyword.get(opts, :name, "player")})
    |> Map.merge(flag_props(flags))
  end

  defp flag_props(flags) do
    for {flag, value} <- flags, into: %{}, do: {prop(flag), value}
  end

  defp prop(:name), do: :username
  defp prop(flag), do: flag
end
