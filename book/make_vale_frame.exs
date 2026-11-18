# Captures a frame of the Vale example, the open-world game, without a window.
#
#     cd cauldron_examples/3d/vale && mix run ../../../book/make_vale_frame.exs
#
# Writes book/assets/vale.png.
#
# The walker is in the frame, so the game is started the way `mix vale` starts it:
# `Vale.Game.prepared/0` loads her rig and clips from the cache (`mix vale.figure` puts
# them there). Without them `posed` is nil and she is never placed.
#
# The camera is the game's own, moved back and turned for the picture. On macOS the
# first `CauldronGPU.open/1` takes the main thread for the VM's life, so this takes one
# picture per run.

alias Cauldron.OpenWorld.Map, as: World
alias Cauldron.OpenWorld.Mover

alias Vale.{Game, Picture}

# The walker starts in the woods. This finds the nearest point of dry beach — ground
# just above the lake's surface — so she stands where the dune meets the sand.
map = Vale.Land.map()
start = Vale.Land.start()

beach =
  for x <- 200..320//2,
      y <- 300..420//2,
      height = World.height(map, {x / 1, y / 1}),
      is_number(height) and height > 0.35 and height < 1.1 do
    {{x / 1, y / 1}, abs(x - elem(start, 0)) + abs(y - elem(start, 1))}
  end
  |> Enum.min_by(fn {_point, distance} -> distance end)
  |> elem(0)

game = Game.init(Game.prepared() ++ [tuning: [distance: 5.5, farthest: 120.0], map: map])
{:ok, game} = Game.join(game, :walker, %{})

viewer = Map.fetch!(game.viewers, :walker)

viewer = %{
  viewer
  | mover: Mover.new(beach, map),
    camera: %{viewer.camera | yaw: 1.6, pitch: -0.24, distance: 5.5}
}

game = %{game | hour: 11.0, viewers: Map.put(game.viewers, :walker, viewer)}

# a second and a half of ticks, so the mixer has a clip and the pose is placed
game = Enum.reduce(1..90, game, fn _, g -> Game.step(g, 1 / 60) end)
view = Game.view(game, :walker)

IO.inspect(view.posed && view.posed.position, label: "walker at")

{:ok, gpu} = CauldronGPU.open(window: false, width: 960, height: 540)
scene = Picture.gpu(view)

# the first frame uploads the looks, the panels and the figure; the ones after it stream
# the cells around the walker, two at a time
{changes, cache} = scene.(gpu, nil, {960, 540}, 960 / 540)
CauldronGPU.submit(gpu, changes)

Enum.reduce(1..20, cache, fn _, cache ->
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
