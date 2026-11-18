# Captures a frame of the Vale example, the open-world game, without a window.
#
#     cd cauldron_examples/3d/vale && mix run ../../../book/make_vale_frame.exs
#
# Writes book/assets/vale.png. `SHOT=lake` takes the other vantage point (morning light
# over the shore). The camera is the game's own, moved back for the picture; the scene is
# `Vale.Picture`'s, drawn on the card and read back with `CauldronGPU.capture/3`.

alias Vale.{Game, Picture}

{name, yaw, pitch, distance, hour} =
  case System.get_env("SHOT", "vista") do
    "lake" -> {"lake", 1.9, -0.35, 25.0, 8.0}
    _ -> {"vista", -0.6, -0.6, 60.0, 12.0}
  end

game = Game.init([])
{:ok, game} = Game.join(game, :walker, %{})

game = %{
  game
  | hour: hour,
    tuning: %{game.tuning | distance: distance, farthest: 120.0, nearest: 2.0}
}

viewer = Map.fetch!(game.viewers, :walker)
camera = %{viewer.camera | yaw: yaw, pitch: pitch, distance: distance}
game = %{game | viewers: Map.put(game.viewers, :walker, %{viewer | camera: camera})}

# a couple of seconds of ticks, so the view has settled and the hour has moved on
game = Enum.reduce(1..120, game, fn _, g -> Game.step(g, 1 / 60) end)
view = Game.view(game, :walker)

{:ok, gpu} = CauldronGPU.open(window: false, width: 960, height: 540)
scene = Picture.gpu(view)

# the first frame uploads the looks, the panels and the figure; the ones after it stream
# the cells around the walker, two at a time
{changes, cache} = scene.(gpu, nil, {960, 540}, 960 / 540)
CauldronGPU.submit(gpu, changes)

Enum.reduce(1..40, cache, fn _, cache ->
  {changes, cache} = scene.(gpu, cache, {960, 540}, 960 / 540)
  CauldronGPU.submit(gpu, changes)
  cache
end)

case CauldronGPU.capture(gpu, 20_000) do
  {:ok, %{width: width, height: height, pixels: pixels}} ->
    path = Path.expand("assets/vale.png", __DIR__)
    File.write!(path, FrenchCurve.Png.encode(width, height, pixels))
    IO.puts("wrote #{path} (#{width}x#{height})")

  {:error, reason} ->
    IO.puts("capture failed: #{inspect(reason)}")
end

CauldronGPU.close(gpu)
