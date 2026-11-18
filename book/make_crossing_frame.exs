# Draws a frame of Crossing for the book.
#
#     cd cauldron_examples/games/crossing && mix run ../../../book/make_crossing_frame.exs
#
# Writes book/assets/crossing.png: the board a few seconds in, the frog out on a log in
# the river. Every tile is the game's own atlas, so the picture cannot drift from the
# game it illustrates.

alias Cauldron2D.{Atlas, Raster, Render}
alias Crossing.{Art, Game, Lanes}

scale = 2
tile = 32 * scale

Art.install()
atlas = Atlas.fetch(Art.name())

picture = fn art -> Atlas.entry(atlas, art).sprite.raster end

# A few seconds in, so the lanes have carts and logs on them, and the frog is out on a
# log in the second water lane.
game = Game.init([])
game = Enum.reduce(1..180, game, fn _, game -> Game.step(game, 1 / 60) end)

lane = Enum.find(game.lanes, &(&1.row == 3))

log =
  lane &&
    (Enum.find(Lanes.items(lane), fn edge -> edge >= 6 and edge <= 9 end) ||
       hd(Lanes.items(lane)))

game = if log, do: %{game | frog: {log + 1.0, 3}}, else: game

view = Game.view(game, :frog)

cell = fn
  {x, 0} -> if(rem(x, 3) == 1, do: :bank, else: :water_a)
  {x, row} when row in 1..5 -> if(rem(x + row, 2) == 0, do: :water_a, else: :water_b)
  {_x, row} when row in 7..11 -> :road
  {x, y} -> Enum.at([:grass_a, :grass_c, :grass_b], rem(x * 7 + y * 13, 3))
end

place = fn art, x, y ->
  {:sprite, picture.(art),
   %{position: {round(x * tile), round(y * tile)}, origin: {0, 0}, scale: {scale, scale}}}
end

ground =
  for y <- 0..12, x <- 0..14 do
    place.(cell.({x, y}), x, y)
  end

kind = fn
  7 -> :car
  8 -> :truck
  9 -> :car
  10 -> :bus
  11 -> :truck
end

parts = fn kind, length, dir ->
  for step <- 0..(length - 1) do
    name = :"#{kind}_#{step}"
    if dir == 1, do: name, else: :"#{name}_w"
  end
end

segment = fn lane, step ->
  if lane.row in 1..5 do
    cond do
      step == 0 -> :log_left
      step == lane.length - 1 -> :log_right
      true -> :log_mid
    end
  else
    Enum.at(parts.(kind.(lane.row), lane.length, lane.dir), step)
  end
end

art = fn lane, step ->
  if lane.row in 1..5 and lane.kind == :turtle do
    if Lanes.surfaced?(lane, view.elapsed), do: :turtle_0, else: :turtle_under
  else
    segment.(lane, step)
  end
end

movers =
  Enum.flat_map(view.lanes, fn lane ->
    Enum.flat_map(Lanes.items(lane), fn edge ->
      shadows =
        for step <- 0..(lane.length - 1), do: place.(:shadow, edge + step, lane.row + 0.28)

      body =
        for step <- 0..(lane.length - 1), do: place.(art.(lane, step), edge + step, lane.row)

      shadows ++ body
    end)
  end)

{fx, fy} = view.frog

frog = [
  place.(:shadow, fx, fy + 0.28),
  place.(:frog, fx, fy),
  place.(:snake_0, view.snake.x, 6)
]

size = {15 * tile, 13 * tile}

frame = Render.render(size, ground ++ movers ++ frog, background: {14, 20, 18, 255})

path = Path.expand("assets/crossing.png", __DIR__)

File.write!(
  path,
  FrenchCurve.Png.encode(elem(size, 0), elem(size, 1), Raster.to_rgba_binary(frame))
)

IO.puts("wrote #{path}")
