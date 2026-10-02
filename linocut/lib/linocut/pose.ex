defmodule Linocut.Pose do
  @moduledoc """
  A figure's joints, and the OpenPose skeleton a ControlNet reads them as.

      Linocut.Pose.skeleton(Linocut.Pose.walk(0.25), {768, 1024})

  A pose is a map of joint name to `{x, y}` with both between `0.0` and `1.0`, measured
  from the picture's top-left. `skeleton/3` draws it in OpenPose's own eighteen-point
  colours on black, which is what `openpose` ControlNets are trained on; feed that picture
  to a model with `preprocess: "as_is"` so it is used as drawn rather than edge-detected.

  `walk/2` gives the joints of a side-on walk at a point in the cycle, so a caller can ask
  for as many frames as it wants and get a cycle that closes.
  """

  alias FrenchCurve.{Draw, Raster}

  @type joint ::
          :nose
          | :neck
          | :right_shoulder
          | :right_elbow
          | :right_wrist
          | :left_shoulder
          | :left_elbow
          | :left_wrist
          | :right_hip
          | :right_knee
          | :right_ankle
          | :left_hip
          | :left_knee
          | :left_ankle
          | :right_eye
          | :left_eye
          | :right_ear
          | :left_ear

  @type t :: %{joint() => {float(), float()}}

  @dots [
    {:nose, {255, 0, 0}},
    {:neck, {255, 85, 0}},
    {:right_shoulder, {255, 170, 0}},
    {:right_elbow, {255, 255, 0}},
    {:right_wrist, {170, 255, 0}},
    {:left_shoulder, {85, 255, 0}},
    {:left_elbow, {0, 255, 0}},
    {:left_wrist, {0, 255, 85}},
    {:right_hip, {0, 255, 170}},
    {:right_knee, {0, 255, 255}},
    {:right_ankle, {0, 170, 255}},
    {:left_hip, {0, 85, 255}},
    {:left_knee, {0, 0, 255}},
    {:left_ankle, {85, 0, 255}},
    {:right_eye, {170, 0, 255}},
    {:left_eye, {255, 0, 255}},
    {:right_ear, {255, 0, 170}},
    {:left_ear, {255, 0, 85}}
  ]

  @limbs [
    {:neck, :right_shoulder, {255, 0, 0}},
    {:neck, :left_shoulder, {255, 85, 0}},
    {:right_shoulder, :right_elbow, {255, 170, 0}},
    {:right_elbow, :right_wrist, {255, 255, 0}},
    {:left_shoulder, :left_elbow, {170, 255, 0}},
    {:left_elbow, :left_wrist, {85, 255, 0}},
    {:neck, :right_hip, {0, 255, 0}},
    {:right_hip, :right_knee, {0, 255, 85}},
    {:right_knee, :right_ankle, {0, 255, 170}},
    {:neck, :left_hip, {0, 255, 255}},
    {:left_hip, :left_knee, {0, 170, 255}},
    {:left_knee, :left_ankle, {0, 85, 255}},
    {:neck, :nose, {0, 0, 255}},
    {:nose, :right_eye, {85, 0, 255}},
    {:right_eye, :right_ear, {170, 0, 255}},
    {:nose, :left_eye, {255, 0, 255}},
    {:left_eye, :left_ear, {255, 0, 170}}
  ]

  @hip_y 0.52
  @neck_y 0.17
  @thigh 0.235
  @shin 0.235
  @upper_arm 0.165
  @forearm 0.165
  @swing 0.42
  @arm_swing 0.34
  @knee 0.95
  @elbow 0.55
  @bob 0.013
  @shoulder_apart 0.012
  @hip_apart 0.010

  @doc """
  The joints of a side-on walk at `phase`, a point in the cycle between `0.0` and `1.0`.

  The figure faces `+x`. The cycle closes: `walk(0.0)` and `walk(1.0)` are the same pose.

  ## Options

    * `:at` — `{x, y}` the hips sit at. Default `{0.5, #{@hip_y}}`
  """
  @spec walk(number(), keyword()) :: t()
  def walk(phase, opts \\ []) do
    {hx, base} = Keyword.get(opts, :at, {0.5, @hip_y})
    turn = 2 * :math.pi() * phase
    hy = base - @bob * :math.cos(2 * turn)
    neck = {hx, hy - (@hip_y - @neck_y)}

    %{}
    |> Map.merge(leg(:right, {hx + @hip_apart, hy}, turn))
    |> Map.merge(leg(:left, {hx - @hip_apart, hy}, turn + :math.pi()))
    |> Map.merge(arm(:right, offset(neck, @shoulder_apart), turn + :math.pi()))
    |> Map.merge(arm(:left, offset(neck, -@shoulder_apart), turn))
    |> Map.put(:neck, neck)
    |> head(neck)
  end

  @doc """
  The pose drawn as an OpenPose skeleton on black, `width` by `height` pixels.

  ## Options

    * `:thickness` — how wide a limb is drawn, as a share of the picture's smaller side.
      Default `0.018`
  """
  @spec skeleton(t(), {pos_integer(), pos_integer()}, keyword()) :: Raster.t()
  def skeleton(pose, {width, height}, opts \\ []) do
    span = min(width, height)
    thick = max(2.0, Keyword.get(opts, :thickness, 0.018) * span)
    canvas = Raster.new(width, height, background: {0, 0, 0, 255})

    canvas
    |> draw_limbs(pose, {width, height}, thick)
    |> draw_dots(pose, {width, height}, thick)
  end

  @doc "The joints a pose names, in OpenPose's own order."
  @spec joints() :: [joint()]
  def joints, do: Enum.map(@dots, &elem(&1, 0))

  defp leg(side, {hx, hy}, turn) do
    thigh = @swing * :math.sin(turn)
    bend = @knee * max(0.0, :math.cos(turn))
    knee = {hx + @thigh * :math.sin(thigh), hy + @thigh * :math.cos(thigh)}
    shin = thigh - bend

    %{
      :"#{side}_hip" => {hx, hy},
      :"#{side}_knee" => knee,
      :"#{side}_ankle" => reach(knee, shin, @shin)
    }
  end

  defp arm(side, {sx, sy}, turn) do
    upper = @arm_swing * :math.sin(turn)
    bend = @elbow * (0.45 + 0.55 * max(0.0, :math.cos(turn)))
    elbow = {sx + @upper_arm * :math.sin(upper), sy + @upper_arm * :math.cos(upper)}

    %{
      :"#{side}_shoulder" => {sx, sy},
      :"#{side}_elbow" => elbow,
      :"#{side}_wrist" => reach(elbow, upper + bend, @forearm)
    }
  end

  defp head(pose, {nx, ny}) do
    Map.merge(pose, %{
      nose: {nx + 0.035, ny - 0.072},
      right_eye: {nx + 0.028, ny - 0.082},
      left_eye: {nx + 0.030, ny - 0.082},
      right_ear: {nx - 0.004, ny - 0.078},
      left_ear: {nx - 0.002, ny - 0.078}
    })
  end

  defp reach({x, y}, angle, length),
    do: {x + length * :math.sin(angle), y + length * :math.cos(angle)}

  defp offset({x, y}, by), do: {x + by, y}

  defp draw_limbs(canvas, pose, size, thick) do
    Enum.reduce(@limbs, canvas, fn {from, to, colour}, acc ->
      with {:ok, start} <- place(pose, from, size),
           {:ok, finish} <- place(pose, to, size) do
        Draw.fill_polygon(acc, bar(start, finish, thick), rgba(colour))
      else
        :missing -> acc
      end
    end)
  end

  defp draw_dots(canvas, pose, size, thick) do
    Enum.reduce(@dots, canvas, fn {joint, colour}, acc ->
      case place(pose, joint, size) do
        {:ok, at} -> Draw.fill_polygon(acc, disc(at, thick * 0.62), rgba(colour))
        :missing -> acc
      end
    end)
  end

  defp place(pose, joint, {width, height}) do
    case Map.fetch(pose, joint) do
      {:ok, {x, y}} -> {:ok, {x * width, y * height}}
      :error -> :missing
    end
  end

  defp bar({x0, y0}, {x1, y1}, thick) do
    {dx, dy} = {x1 - x0, y1 - y0}
    span = max(1.0e-6, :math.sqrt(dx * dx + dy * dy))
    {nx, ny} = {-dy / span * thick / 2, dx / span * thick / 2}

    [{x0 + nx, y0 + ny}, {x1 + nx, y1 + ny}, {x1 - nx, y1 - ny}, {x0 - nx, y0 - ny}]
  end

  defp disc({cx, cy}, radius) do
    for step <- 0..11 do
      angle = 2 * :math.pi() * step / 12
      {cx + radius * :math.cos(angle), cy + radius * :math.sin(angle)}
    end
  end

  defp rgba({r, g, b}), do: {r, g, b, 255}
end
