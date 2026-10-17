defmodule BrowserQuake do
  @moduledoc """
  A Quake map in a browser, uploaded with the same `CauldronGPU.Bsp.upload/4` a native
  renderer uses: served at http://localhost:4400/, the camera at the player start turning
  slowly, the map's light styles flickering.

      mix run examples/quake_map.exs ~/quake e1m1 [seconds]

  The first argument is the game directory (holding `id1`).
  """

  alias Cauldron3D.Formats.{Bsp, Entities, Files}
  alias Cauldron3D.Net.Scene
  alias CauldronGPU.{Camera, Environment}

  defmodule Socket do
    @moduledoc false
    use Cauldron3D.Net.Socket, channel: BrowserQuake.Channel
  end

  defmodule Channel do
    @moduledoc false
    use Cauldron3D.Net.Channel
  end

  defmodule Endpoint do
    @moduledoc false
    use Phoenix.Endpoint, otp_app: :cauldron_3d_net

    socket("/socket", BrowserQuake.Socket, websocket: true, longpoll: false)
    plug(Cauldron3D.Net.Page, scene: "quake", title: "quake map")
  end

  @tick_ms 50
  @styles ["m", "mmamammmmammamamaaamammma", "abcdefghijklmnopqrstuvwxyzyxwvutsrqponmlkjihgfedcba",
           "mmmmmaaaaammmmmaaaaaabcdefgabcdefg", "mamamamamama", "jklmnopqrstuvwxyzyxwvutsrqponmlkj",
           "nmonqnmomnmomomno", "mmmaaaabcdefgmmmmaaaammmaamm", "mmmaaammmaaammmabcdefaaaammmmabcdefmmmaaaa",
           "aaaaaaaazzzzzzzz", "mmamammmmammamamaaamammma", "abcdefghijklmnopqrrqponmlkjihgfedcba"]

  def run([directory, map | rest]) do
    Application.put_env(:cauldron_3d_net, Endpoint,
      adapter: Bandit.PhoenixAdapter,
      http: [port: 4400],
      server: true,
      secret_key_base: String.duplicate("cauldron", 8),
      pubsub_server: Cauldron3D.Net.PubSub
    )

    {:ok, _} = Endpoint.start_link()
    {:ok, files} = Files.open(Path.expand(directory), within: "id1")
    palette = binary_part(Files.read(files, "gfx/palette.lmp"), 0, 768)
    {:ok, %{bsp: bsp, entities: text}} = Bsp.parse(Files.read(files, "maps/#{map}.bsp"), texture: &texture/2)
    {:ok, scene} = Scene.open(id: "quake")
    world = CauldronGPU.Bsp.upload(scene, bsp, palette)
    {origin, angle} = spawn_point(Entities.parse(text))
    environment = %Environment{ambient_intensity: 0.0, reflections: 0.0, tone_map: :neutral, sky_picture: CauldronGPU.Bsp.sky_layers(scene, bsp, palette)}
    Scene.submit(scene, [environment | CauldronGPU.Bsp.instances(world)])
    IO.puts("watch at http://localhost:4400/")
    eye = CauldronGPU.Bsp.point(world, {elem(origin, 0), elem(origin, 1), elem(origin, 2) + 22})
    deadline = with [seconds] <- rest, do: System.monotonic_time(:millisecond) + String.to_integer(seconds) * 1000
    loop(scene, eye, angle, 0, deadline)
  end

  defp loop(scene, eye, angle, tick, deadline) do
    if deadline && System.monotonic_time(:millisecond) >= deadline do
      :done
    else
      seconds = tick * @tick_ms / 1000
      styles = Enum.map(@styles, &CauldronGPU.Bsp.light_style(&1, seconds))
      camera = %Camera{position: eye, rotation: CauldronGPU.Bsp.facing(angle + tick * 0.5), fov_y: 1.3}
      Scene.submit(scene, [{:light_styles, styles}, camera])
      Process.sleep(@tick_ms)
      loop(scene, eye, angle, tick + 1, deadline)
    end
  end

  defp texture(name, mips) do
    kind =
      cond do
        String.starts_with?(name, "sky") -> :sky
        String.starts_with?(name, "*") -> :liquid
        name in ["trigger", "clip", "hint", "skip"] -> :hidden
        String.starts_with?(name, "{") -> :masked
        true -> :solid
      end

    %{Bsp.solid(name, mips) | kind: kind}
  end

  defp spawn_point(entities) do
    start = Enum.find(entities, &(&1["classname"] == "info_player_start")) || %{}
    [x, y, z] = (start["origin"] || "0 0 0") |> String.split() |> Enum.map(&parse_number/1)
    {{x, y, z}, parse_number(start["angle"] || "0")}
  end

  defp parse_number(text) do
    case Float.parse(text) do
      {value, _} -> value
      :error -> 0.0
    end
  end
end

BrowserQuake.run(System.argv())
