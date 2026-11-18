# Draws a frame of Crossing for the book.
#
#     cd cauldron_examples/games/crossing && mix run ../../../book/make_crossing_frame.exs
#
# Writes book/assets/crossing.png: the board a few seconds in, the frog half way across
# the river on a log. The tiles are the game's own atlas, so the picture cannot drift
# from the game it illustrates.

alias Cauldron2D.{Atlas, Render}
alias Crossing.{Art, Game, Lanes}

scale = 3
tile = 16 * scale

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
    (Enum.find(Lanes.items(lane), fn edge -> edge >= 8 and edge <= 12 end) ||
       hd(Lanes.items(lane)))

game = if log, do: %{game | frog: {log + 1.0, 3}}, else: game

view = Game.view(game, :frog)

cell = fn
  {_x, 0} -> :bank
  {_x, row} when row in 2..5 -> :water
  {_x, row} when row in 7..10 -> :road
  {_x, _row} -> :grass
end

background =
  for y <- 0..14, x <- 0..14 do
    {:sprite, picture.(cell.({x, y})), %{position: {x * tile, y * tile}, origin: {0, 0}, scale: {scale, scale}}}
  end

movers =
  Enum.flat_map(view.lanes, fn lane ->
    art = if lane.row in 2..5, do: :log, else: :cart

    Enum.flat_map(Lanes.items(lane), fn edge ->
      for step <- 0..(lane.length - 1) do
        {:sprite, picture.(art),
         %{position: {round((edge + step) * tile), lane.row * tile}, origin: {0, 0}, scale: {scale, scale}}}
      end
    end)
  end)

{fx, fy} = view.frog

frog = [
  {:sprite, picture.(:frog),
   %{position: {round(fx * tile), round(fy * tile)}, origin: {0, 0}, scale: {scale, scale}}}
]

size = {15 * tile, 15 * tile}

frame =
  Render.render(size, background ++ movers ++ frog, background: {16, 22, 20, 255})

path = Path.expand("assets/crossing.png", __DIR__)
File.write!(path, FrenchCurve.Png.encode(elem(size, 0), elem(size, 1), Cauldron2D.Raster.to_rgba_binary(frame)))
IO.puts("wrote #{path}")
