alias Cauldron2D.{Draw, Raster}
Crossing.Client.atlas()
game = Crossing.Game.init([]) |> Crossing.Game.step(1.3)
scene = Crossing.Client.scene(Crossing.Game.view(game, nil), %{})
look = %{projection: :top}
view = Draw.new(Draw.props(Crossing.Client, scene, look, 1))
IO.inspect(view.projection, label: "projection")
IO.inspect(view.native, label: "native")
for {name, size, aspect} <- [{"wide", {1434, 832}, 1.0}, {"tall", {700, 1100}, 1.0}, {"cells_quad", {160, 90}, 0.5}] do
  raster = Draw.drawn(view, size, aspect, :kitty, 0)
  {w, h} = Raster.dimensions(raster)
  File.write!(".scratch/field_#{name}.png", FrenchCurve.Png.encode(w, h, Raster.to_rgba_binary(raster)))
  IO.puts("#{name}: #{w}x#{h}")
end
{us, _} = :timer.tc(fn -> Draw.drawn(view, {1434, 832}, 1.0, :kitty, 0) end)
IO.puts("wide frame ms: #{us / 1000}")
