defmodule Cauldron3D.Billboard do
  @moduledoc """
  A flat picture standing in the world, turned to face the camera.

      Cauldron3D.Billboard.polygon(view, {128.0, 0.0, 32.0}, texture, origin: {16, 32})

  The picture's pixel `origin` (default its centre) sits at `position`; one pixel is one
  world unit times `:scale`. `:upright` (default false) keeps it standing straight up
  and only turned about `z`, as a tree or a torch flame is.
  """

  alias Cauldron3D.{Polygon, Texture, Vec, View}

  @doc """
  The picture as a polygon facing `view`. Options: `:origin`, `:scale`, `:upright`,
  `:light` (as `{:texture, texture, light}` takes, default `nil`), `:clear` (default 255)
  and `:depth`.
  """
  @spec polygon(View.t(), Vec.t(), Texture.t(), keyword()) :: Polygon.t()
  def polygon(%View{} = view, position, %Texture{} = texture, opts \\ []) do
    {ox, oy} = Keyword.get(opts, :origin, {texture.width / 2, texture.height / 2})
    scale = Keyword.get(opts, :scale, 1.0)
    {right, up} = axes(view, Keyword.get(opts, :upright, false))
    position = Vec.float(position)

    corner = fn x, y ->
      position
      |> Vec.madd(right, (x - ox) * scale)
      |> Vec.madd(up, (oy - y) * scale)
    end

    {w, h} = {texture.width, texture.height}

    %Polygon{
      points: [corner.(0, 0), corner.(w, 0), corner.(w, h), corner.(0, h)],
      uvs: [{0.0, 0.0}, {w / 1, 0.0}, {w / 1, h / 1}, {0.0, h / 1}],
      paint: {:texture, texture, Keyword.get(opts, :light)},
      clear: Keyword.get(opts, :clear, 255),
      depth: Keyword.get(opts, :depth, :test)
    }
  end

  defp axes(view, false), do: {view.right, view.up}

  defp axes(view, true) do
    {rx, ry, _} = view.right
    {Vec.normalize({rx, ry, 0.0}), {0.0, 0.0, 1.0}}
  end
end
