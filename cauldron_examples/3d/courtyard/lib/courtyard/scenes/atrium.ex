defmodule Courtyard.Scenes.Atrium do
  @moduledoc """
  Intel's Sponza: the atrium of arches, columns and galleries, lit by a sun that crosses
  the open roof as the view's `:hour` runs from sunrise (6) to sunset (18), its light and
  the sky warming and dimming towards the horizon. A `Courtyard.Scene`;
  `mix courtyard.fetch atrium` downloads it. Intel Sponza is © Intel Corporation, under
  the Creative Commons Attribution licence.

  Options: `:side`, the texture size to load (2048, the default, or 1024).

      {:ok, placed} = Courtyard.Scenes.Atrium.upload(target, side: 1024)
  """

  @behaviour Courtyard.Scene

  alias Cauldron3D.Scene.{Environment, Gltf, Light, Transform}
  alias Cauldron3D.WalkGrid
  alias Courtyard.{Assets, Grounds}

  @first_id 2000
  @sun 1

  @impl true
  def name, do: "atrium"

  @impl true
  def start, do: %{position: {-9.0, 0.0, 0.0}, yaw: -:math.pi() / 2, pitch: -0.15}

  @impl true
  def ground do
    with true <- Assets.ready?(:atrium) || {:error, {:missing, Assets.fetch_command(:atrium)}},
         do: Grounds.cached(:atrium, &walk_grid/0)
  end

  defp walk_grid do
    with {:ok, document} <- Cauldron3D.Formats.Gltf.read(Assets.atrium(1024)) do
      sources = Grounds.sources(document, [%Transform{}])
      {:ok, WalkGrid.build({{-16.3, -9.5}, {20.1, 14.5}}, sources)}
    end
  end

  @impl true
  def upload(target, opts) do
    side = Keyword.get(opts, :side, 2048)

    with true <- Assets.ready?(:atrium) || {:error, {:missing, Assets.fetch_command(:atrium)}},
         {:ok, document} <- Cauldron3D.Formats.Gltf.read(Assets.atrium(side)),
         {:ok, result} <- Gltf.upload(target, document, first_id: @first_id) do
      {:ok, %{changes: result.instances, handles: result.handles, data: result.bounds}}
    end
  end

  @impl true
  def frame(_placed, view), do: sunlit(Map.get(view, :hour, 13.0))

  @doc "The sun light and the sky for `hour`, from 6 (sunrise) to 18 (sunset)."
  @spec sunlit(number()) :: [Cauldron3D.Scene.Stream.change()]
  def sunlit(hour) do
    angle = (hour - 6.0) / 12.0 * :math.pi()
    height = max(:math.sin(angle), 0.02)
    {x, y, z} = normalized({:math.cos(angle) * 0.75, height, 0.35})
    warmth = 1.0 - min(height * 2.0, 1.0)

    [
      {:light, @sun,
       %Light{
         kind: :directional,
         direction: {-x, -y, -z},
         color: {1.0, 0.95 - 0.35 * warmth, 0.85 - 0.6 * warmth},
         intensity: 0.4 + 5.0 * height,
         shadows: true
       }},
      %Environment{
        sky_top: mix({0.25, 0.45, 0.85}, {0.12, 0.15, 0.3}, warmth),
        sky_horizon: mix({0.75, 0.85, 0.95}, {0.95, 0.55, 0.35}, warmth),
        sky_ground: {0.25, 0.22, 0.2},
        ambient: mix({0.45, 0.5, 0.6}, {0.5, 0.35, 0.3}, warmth),
        ambient_intensity: 0.08 + 0.2 * height,
        exposure: 1.2,
        shadow_distance: 40.0,
        bloom_strength: 0.04
      }
    ]
  end

  defp normalized({x, y, z}) do
    length = :math.sqrt(x * x + y * y + z * z)
    {x / length, y / length, z / length}
  end

  defp mix({ar, ag, ab}, {br, bg, bb}, amount),
    do: {ar + (br - ar) * amount, ag + (bg - ag) * amount, ab + (bb - ab) * amount}
end
