defmodule Mix.Tasks.Courtyard do
  @shortdoc "Walk through a lit 3D courtyard in this terminal"

  @moduledoc """
  Walk a character through the courtyard in the terminal, drawn by the graphics card.
  Before the client starts, the character (`Courtyard.Character`) and every downloaded
  scene's walk grid (`Courtyard.Grounds`) are loaded for the world; a grid not yet built
  takes seconds and is kept for later.

      mix courtyard
      mix courtyard --window

  `Courtyard.Client` lists the keys. Flags:

    * `--window` — draw in a window of its own, whose keys drive the scene
    * `--gpu` — draw on the graphics card in the terminal, whatever the saved drawing
      setting says
    * `--name` — the player name settings are kept under; default `viewer`
    * `--mute`, `--picture`, `--trace` — as `Cauldron2D.Drafter.Play` takes them; the
      sound is off unless `--no-mute` is given
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [window: :boolean, gpu: :boolean])
    Mix.Task.run("app.start")

    Play.run(Courtyard.Client, argv,
      name: "viewer",
      refresh_rate: "60fps",
      props: %{picture: picture(card(opts)), mute: true, world: Courtyard.Game.prepared()}
    )
  end

  defp picture([]), do: nil
  defp picture(card), do: Courtyard.Client.look().picture ++ card

  defp card(opts) do
    for {switch, option} <- [gpu: :gpu, window: :window],
        Keyword.get(opts, switch, false),
        do: option
  end
end
