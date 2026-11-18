[client, world_id, out | rest] = System.argv()
game = Module.concat([client])

frames =
  case rest do
    [n | _] -> String.to_integer(n)
    [] -> 40
  end

alias Cauldron.Client.{Fronts, Stage}
alias Cauldron.Player
alias Cauldron.World
alias Cauldron2D.Client.Look
alias Cauldron2D.Draw
alias Cauldron2D.Net.{Atlas, Scene}

File.mkdir_p!(out)
name = game.atlas()
atlas = Atlas.cached(name)
rgba = fn raster -> FrenchCurve.Raster.to_rgba_binary(raster) end
{:ok, sheet} = Linocut.Png.decode(atlas.png)
File.write!(Path.join(out, "atlas.json"), Jason.encode!(atlas.index))
File.write!(Path.join(out, "atlas.rgba"), rgba.(sheet))

write_scene = fn label, view, pane, at ->
  {_writer, payload} = Scene.write(Scene.writer(), view, pane, at: at)
  json = payload |> Jason.encode!() |> Jason.decode!()
  {_reader, read} = Scene.read(Scene.reader(name), json)
  picture = Draw.picture(read, pane, at: at)
  dir = Path.join(out, label)
  File.mkdir_p!(dir)

  File.write!(
    Path.join(dir, "scene.json"),
    Jason.encode!(%{
      payload: payload,
      pane: Tuple.to_list(pane),
      at: at,
      width: picture.width,
      height: picture.height
    })
  )

  File.write!(Path.join(dir, "expected.rgba"), rgba.(picture))

  for [art, tint] <- payload.tints, built = Atlas.tinted(name, art, tint), built != nil do
    {:ok, raster} = Linocut.Png.decode(built.png)
    base = Path.join(dir, "tinted-#{tint}-#{Base.url_encode64(art, padding: false)}")

    File.write!(
      base <> ".json",
      Jason.encode!(%{
        art: art,
        tint: tint,
        index: built.index,
        width: raster.width,
        height: raster.height
      })
    )

    File.write!(base <> ".rgba", rgba.(raster))
  end

  for [base, overlays, tint] <- payload.tinted_cells,
      built = Atlas.tinted_cell(name, base, overlays, tint),
      built != nil do
    {:ok, raster} = Linocut.Png.decode(built.png)

    file =
      "tintedcell-#{tint}-#{Base.url_encode64(Enum.join([base | overlays], "\0"), padding: false)}"

    File.write!(
      Path.join(dir, file <> ".json"),
      Jason.encode!(%{
        base: base,
        overlays: overlays,
        tint: tint,
        index: built.index,
        width: raster.width,
        height: raster.height
      })
    )

    File.write!(Path.join(dir, file <> ".rgba"), rgba.(raster))
  end

  IO.puts("#{label}: #{picture.width}x#{picture.height}")
end

pane = {60, 34}
at = 4_321
world = Enum.find(game.worlds(%{}), &(to_string(&1.id) == world_id))

{pid, _} =
  case world.world do
    {module, opts} -> {elem(World.start_link([game: module] ++ opts), 1), :own}
    name -> {GenServer.whereis(name), :shared}
  end

:ok = Player.join(pid, "fixture", %{username: "fixture"})

for _ <- 1..frames,
    do: receive(do: ({:cauldron_frame, _} -> :ok), after: (3000 -> raise "no frame"))

view =
  receive do
    {:cauldron_frame, %{view: view}} -> view
  after
    3000 -> raise "no frame"
  end

stage = Stage.new(game, %{sfx: 0.0, music: 0.0}) |> Stage.view(view)

for projection <- stage.look.projections do
  stage = %{stage | look: %{stage.look | projection: projection}}
  scene = Stage.scene(stage)
  drawn = Draw.new(Stage.draw_props(stage, scene))
  if Scene.drawable?(drawn), do: write_scene.("play-#{projection}", drawn, pane, at)
end

if Cauldron.Client.Menus.menu?(game) do
  {menued, _} = Stage.key(%{stage | keys: Map.put(stage.keys, :menu, :m)}, :m)
  write_scene.("menu", Draw.new(Stage.draw_props(menued, Stage.scene(menued))), pane, at)
end

fronts = Fronts.of(game, %{})

for {screen, _module} <- fronts do
  state = %{screen: screen, fronts: fronts, front: nil}

  context = %{
    settings: stage.settings,
    username: "fixture",
    worlds: game.worlds(%{}),
    outcome: %{
      score: 120,
      deaths: 2,
      stage: 3,
      won?: false,
      title: "OVER",
      lines: ["a"],
      next: :lobby
    },
    view: view
  }

  {state, _} = Fronts.open(state, context, 0)
  state = Fronts.tick(state, 2_000)
  look = Cauldron.Client.View.given(Look.of(game), nil, 0, stage.settings.options)
  drawn = Draw.new(Draw.props(game, Fronts.scene(state), look, Look.zoom(game)))
  if Scene.drawable?(drawn), do: write_scene.("front-#{screen}", drawn, pane, at)
end

System.halt(0)
