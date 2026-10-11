defmodule Cauldron3D.View do
  @moduledoc """
  A camera fitted to a picture: the projection from the world to pixels.

      view = Cauldron3D.View.new(camera, {320, 200})
      Cauldron3D.View.to_camera(view, point)

  Pixel `{0, 0}` is the top left. `:pixel_aspect` is a pixel's height over its width,
  1.0 for square pixels; a taller pixel squeezes the picture's height so circles stay
  round.

  A point in camera space is `{right, up, depth}`. Projected, it is
  `{x, y, nearness, w}`: the pixel position, a value that grows toward the camera and
  changes linearly across the picture (for comparing what is in front), and the factor
  attributes are carried through by for perspective-correct interpolation (`1 / depth`
  in perspective, `1.0` orthographic).
  """

  alias Cauldron3D.{Camera, Vec}

  @type t :: %__MODULE__{
          camera: Camera.t(),
          width: pos_integer(),
          height: pos_integer(),
          origin: Vec.t(),
          forward: Vec.t(),
          right: Vec.t(),
          up: Vec.t(),
          center_x: float(),
          center_y: float(),
          scale_x: float(),
          scale_y: float(),
          near: float(),
          perspective?: boolean()
        }

  defstruct [
    :camera,
    :width,
    :height,
    :origin,
    :forward,
    :right,
    :up,
    :center_x,
    :center_y,
    :scale_x,
    :scale_y,
    :near,
    :perspective?
  ]

  @doc "The view of `camera` in a picture `{width, height}`. Takes `:pixel_aspect`, default 1.0."
  @spec new(Camera.t(), {pos_integer(), pos_integer()}, keyword()) :: t()
  def new(%Camera{} = camera, {width, height}, opts \\ []) do
    aspect = Keyword.get(opts, :pixel_aspect, 1.0)
    {forward, right, up} = Camera.basis(camera)
    perspective? = camera.projection == :perspective

    scale_x =
      if perspective?,
        do: width / 2 / :math.tan(camera.fov / 2),
        else: width / camera.extent

    %__MODULE__{
      camera: camera,
      width: width,
      height: height,
      origin: camera.position,
      forward: forward,
      right: right,
      up: up,
      center_x: width / 2,
      center_y: height / 2,
      scale_x: scale_x,
      scale_y: scale_x / aspect,
      near: camera.near,
      perspective?: perspective?
    }
  end

  @doc "A world point in camera space, `{right, up, depth}`."
  @spec to_camera(t(), Vec.t()) :: Vec.t()
  def to_camera(%__MODULE__{} = view, point) do
    offset = Vec.sub(point, view.origin)
    {Vec.dot(offset, view.right), Vec.dot(offset, view.up), Vec.dot(offset, view.forward)}
  end

  @doc "A camera-space point projected: `{x, y, nearness, w}`. The depth must be above zero in perspective."
  @spec project(t(), Vec.t()) :: {float(), float(), float(), float()}
  def project(%__MODULE__{perspective?: true} = view, {cx, cy, depth}) do
    w = 1 / depth
    {view.center_x + cx * w * view.scale_x, view.center_y - cy * w * view.scale_y, w, w}
  end

  def project(%__MODULE__{} = view, {cx, cy, depth}),
    do: {view.center_x + cx * view.scale_x, view.center_y - cy * view.scale_y, -depth, 1.0}

  @doc "The direction from the camera through the centre of pixel `{x, y}`, in the world, not of length one."
  @spec ray(t(), number(), number()) :: Vec.t()
  def ray(%__MODULE__{} = view, x, y) do
    view.forward
    |> Vec.madd(view.right, (x + 0.5 - view.center_x) / view.scale_x)
    |> Vec.madd(view.up, (view.center_y - y - 0.5) / view.scale_y)
  end

  @doc "Whether a point in the world is in front of the camera's near plane."
  @spec in_front?(t(), Vec.t()) :: boolean()
  def in_front?(%__MODULE__{} = view, point),
    do: Vec.dot(Vec.sub(point, view.origin), view.forward) >= view.near
end
