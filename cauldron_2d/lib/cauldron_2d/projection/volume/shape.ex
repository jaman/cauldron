defmodule Cauldron2D.Projection.Volume.Shape do
  @moduledoc """
  What a projection needs to know about the shape of a `Cauldron2D.Projection.Volume`.

  A shape is a module and a term it understands, `{MyShapes, {:wedge, 4.0}}`. The three
  callbacks work in the volume's own space: the origin is the volume's place on the
  ground and `z` runs up from there, so a shape says nothing about where in the world it
  stands.

  `Cauldron2D.Projection.Volume.Shapes` implements the shapes the engine ships with. A
  game with a shape of its own implements this behaviour and names its module in the
  volume.

      defmodule MyGame.Shapes do
        @behaviour Cauldron2D.Projection.Volume.Shape

        @impl true
        def span({:slab, half}, {_x, _y, oz}, {_dx, _dy, dz}) do
          ...
        end
      end

  Nothing below the ground is drawn, so a shape need not clip itself to `z >= 0`; the
  volume does that.
  """

  @type point :: {number(), number(), number()}

  @doc """
  The stretches of the ray `origin + t * direction` that lie inside the shape, as
  `{from, to}` pairs of `t`.

  The pairs must not overlap and must run in order. An empty list means the ray misses.
  """
  @callback span(term(), point(), point()) :: [{number(), number()}]

  @doc """
  The box the shape fits in, as `{{min_x, min_y, min_z}, {max_x, max_y, max_z}}`.

  A projection uses it to find the part of the picture the volume can reach, so it must
  hold every point of the shape.
  """
  @callback bounds(term()) :: {point(), point()}

  @doc """
  How far a ray travels through the thickest part of the shape.

  This is the length at which the volume tints by its full strength; a shorter crossing
  tints less and a longer one no more.
  """
  @callback thickness(term()) :: number()
end
