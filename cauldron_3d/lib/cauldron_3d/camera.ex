defmodule Cauldron3D.Camera do
  @moduledoc """
  Where a picture is taken from: a position, a facing, and a projection.

  The world is right-handed with `z` up. `yaw` turns about `z`, 0 facing `+x` and
  `:math.pi() / 2` facing `+y`; `pitch` above zero looks up; `roll` above zero tips the
  picture clockwise. A `:perspective` camera sees `fov` radians across; an
  `:orthographic` one sees `extent` world units across, the same at every distance.

      Cauldron3D.Camera.first_person({0.0, 0.0, 56.0}, yaw, pitch)
      Cauldron3D.Camera.follow(target, yaw, distance: 120.0, height: 40.0)
      Cauldron3D.Camera.side(target, extent: 640.0)
      Cauldron3D.Camera.top_down(target, extent: 1024.0)
  """

  alias Cauldron3D.Vec

  @type projection :: :perspective | :orthographic
  @type t :: %__MODULE__{
          position: Vec.t(),
          yaw: float(),
          pitch: float(),
          roll: float(),
          projection: projection(),
          fov: float(),
          extent: float(),
          near: float()
        }

  defstruct position: {0.0, 0.0, 0.0},
            yaw: 0.0,
            pitch: 0.0,
            roll: 0.0,
            projection: :perspective,
            fov: :math.pi() / 2,
            extent: 512.0,
            near: 1.0

  @doc """
  A camera from options: `:position`, `:yaw`, `:pitch`, `:roll`, `:projection`, `:fov`,
  `:extent` and `:near`, each defaulting as the struct does.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    camera = struct!(__MODULE__, opts)
    %{camera | position: Vec.float(camera.position)}
  end

  @doc "A perspective camera at `position` looking along `yaw` and `pitch`. Takes `new/1`'s options."
  @spec first_person(Vec.t(), number(), number(), keyword()) :: t()
  def first_person(position, yaw, pitch, opts \\ []) do
    new([position: position, yaw: yaw / 1, pitch: pitch / 1] ++ opts)
  end

  @doc """
  A perspective camera behind `target`, facing along `yaw` and looking down at it.

  ## Options

    * `:distance` — how far behind, default 128.0
    * `:height` — how far above the target the camera sits, default 48.0
    * `:look_height` — the height above the target the camera aims at, default 0.0
    * anything `new/1` takes
  """
  @spec follow(Vec.t(), number(), keyword()) :: t()
  def follow(target, yaw, opts \\ []) do
    {distance, opts} = Keyword.pop(opts, :distance, 128.0)
    {height, opts} = Keyword.pop(opts, :height, 48.0)
    {look_height, opts} = Keyword.pop(opts, :look_height, 0.0)
    {tx, ty, tz} = Vec.float(target)
    position = {tx - :math.cos(yaw) * distance, ty - :math.sin(yaw) * distance, tz + height}
    pitch = :math.atan2(look_height - height, distance)
    new([position: position, yaw: yaw / 1, pitch: pitch] ++ opts)
  end

  @doc """
  An orthographic camera looking across the world at `target` from the `-y` side, as a
  side-scroller sees it. `:extent` (default 512.0) is how wide the view is; `:distance`
  (default 4096.0) how far back it stands.
  """
  @spec side(Vec.t(), keyword()) :: t()
  def side(target, opts \\ []) do
    {distance, opts} = Keyword.pop(opts, :distance, 4096.0)
    {tx, ty, tz} = Vec.float(target)

    new(
      [
        position: {tx, ty - distance, tz},
        yaw: :math.pi() / 2,
        pitch: 0.0,
        projection: :orthographic
      ] ++
        opts
    )
  end

  @doc """
  An orthographic camera looking straight down at `target`, `+y` at the top of the
  picture. `:extent` (default 512.0) is how wide the view is; `:distance` (default
  4096.0) how high it hangs.
  """
  @spec top_down(Vec.t(), keyword()) :: t()
  def top_down(target, opts \\ []) do
    {distance, opts} = Keyword.pop(opts, :distance, 4096.0)
    {tx, ty, tz} = Vec.float(target)

    new(
      [
        position: {tx, ty, tz + distance},
        yaw: :math.pi() / 2,
        pitch: -:math.pi() / 2,
        projection: :orthographic
      ] ++ opts
    )
  end

  @doc """
  The camera's axes in the world: `{forward, right, up}`, each of length one.
  """
  @spec basis(t()) :: {Vec.t(), Vec.t(), Vec.t()}
  def basis(%__MODULE__{yaw: yaw, pitch: pitch, roll: roll}) do
    {sy, cy} = {:math.sin(yaw), :math.cos(yaw)}
    {sp, cp} = {:math.sin(pitch), :math.cos(pitch)}
    forward = {cp * cy, cp * sy, sp}
    level_right = {sy, -cy, 0.0}
    level_up = Vec.cross(level_right, forward)
    {sr, cr} = {:math.sin(roll), :math.cos(roll)}
    right = Vec.add(Vec.scale(level_right, cr), Vec.scale(level_up, -sr))
    up = Vec.add(Vec.scale(level_right, sr), Vec.scale(level_up, cr))
    {forward, right, up}
  end

  @doc "The direction `yaw` and `pitch` face, of length one."
  @spec forward(number(), number()) :: Vec.t()
  def forward(yaw, pitch),
    do: {:math.cos(pitch) * :math.cos(yaw), :math.cos(pitch) * :math.sin(yaw), :math.sin(pitch)}
end
