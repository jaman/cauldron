defmodule Mix.Tasks.Vale do
  @shortdoc "Walk an open land in this terminal"

  @moduledoc """
  Walk a small figure about the vale in the terminal, drawn by the graphics card. Before
  the client starts, the land is made (`Vale.Land`) and the figure's rig and clips are
  read (`Vale.Figure`; `mix vale.figure` copies them in).

      mix vale
      mix vale --window

  `Vale.Client` lists the keys. Flags:

    * `--window` — draw in a window of its own, whose keys drive the scene
    * `--gpu` — draw on the graphics card in the terminal, whatever the saved drawing
      setting says
    * `--name` — the player name settings are kept under; default `walker`
    * `--mute`, `--picture`, `--trace` — as `Cauldron2D.Drafter.Play` takes them; the
      sound is off unless `--no-mute` is given
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [window: :boolean, gpu: :boolean])
    Mix.Task.run("app.start")
    Vale.Land.map()

    Play.run(Vale.Client, argv,
      name: "walker",
      refresh_rate: "60fps",
      props: %{picture: picture(card(opts)), mute: true, world: Vale.Game.prepared()}
    )
  end

  defp picture([]), do: nil
  defp picture(card), do: Vale.Client.look().picture ++ card

  defp card(opts) do
    for {switch, option} <- [gpu: :gpu, window: :window],
        Keyword.get(opts, switch, false),
        do: option
  end
end
