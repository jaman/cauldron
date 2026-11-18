defmodule Cauldron3D.Formats.Gltf.Clip do
  @moduledoc """
  Plays a clip read by `Cauldron3D.Formats.Gltf.Animations`.

  `sample/3` gives what a clip sets at one time, by node index:

    * `translations` — node => `{x, y, z}`
    * `rotations` — node => `{x, y, z, w}`
    * `scales` — node => `{x, y, z}`
    * `weights` — node => morph target weights

  Nodes the clip does not move are absent. Times before the first keyframe give the first
  value and times after the last give the last.

  `blend/3` mixes two samples; a node in only one of them takes that one's value unchanged.
  `Cauldron3D.Formats.Gltf.Rig.pose_sample/3` puts a sample on a rig.

  A clip read from one file plays on a figure read from another with the same bone
  names once `onto/3` has renamed its nodes, and `without/3` takes a channel out of a
  clip, such as the hips' travel.

      [walk, run] = document.animations
      sample = Cauldron3D.Formats.Gltf.Clip.sample(walk, 0.4, loop: true)
      mixed = Cauldron3D.Formats.Gltf.Clip.blend(sample, Cauldron3D.Formats.Gltf.Clip.sample(run, 0.4), 0.25)
  """

  alias Cauldron3D.Quat

  @type sample :: %{
          translations: %{non_neg_integer() => {float(), float(), float()}},
          rotations: %{non_neg_integer() => Quat.t()},
          scales: %{non_neg_integer() => {float(), float(), float()}},
          weights: %{non_neg_integer() => [float()]}
        }

  @fields %{translation: :translations, rotation: :rotations, scale: :scales, weights: :weights}

  @doc """
  What `clip` sets at `time` seconds. With `loop: true` the time wraps around the clip's
  duration.
  """
  @spec sample(map(), number(), keyword()) :: sample()
  def sample(%{channels: channels, duration: duration}, time, opts \\ []) do
    time = wrapped(time, duration, Keyword.get(opts, :loop, false))

    Enum.reduce(channels, empty(), fn channel, sample ->
      field = Map.fetch!(@fields, channel.path)
      Map.update!(sample, field, &Map.put(&1, channel.node, value(channel, time)))
    end)
  end

  @doc "`first` and `second` mixed, `amount` (0 to 1) of the way to `second`."
  @spec blend(sample(), sample(), number()) :: sample()
  def blend(first, second, amount) do
    %{
      translations: merged(first.translations, second.translations, &lerp(&1, &2, amount)),
      rotations: merged(first.rotations, second.rotations, &Quat.slerp(&1, &2, amount / 1)),
      scales: merged(first.scales, second.scales, &lerp(&1, &2, amount)),
      weights: merged(first.weights, second.weights, &lerp_list(&1, &2, amount))
    }
  end

  @doc """
  `clip`, read from the document `from`, for the document `onto`: each channel moves the
  node of `onto` that has the name of its node in `from`. Channels whose node `onto` has
  no namesake for are left out.
  """
  @spec onto(map(), Cauldron3D.Formats.Gltf.t(), Cauldron3D.Formats.Gltf.t()) :: map()
  def onto(%{channels: channels} = clip, from, onto) do
    names = from.nodes |> Enum.with_index() |> Map.new(fn {node, index} -> {index, node.name} end)

    places =
      onto.nodes |> Enum.with_index() |> Map.new(fn {node, index} -> {node.name, index} end)

    moved =
      for channel <- channels,
          name = Map.get(names, channel.node),
          place = Map.get(places, name),
          name != nil and place != nil,
          do: %{channel | node: place}

    %{clip | channels: moved}
  end

  @doc "`clip` without its channel of `path` (`:translation`, `:rotation`, `:scale` or `:weights`) for `node`."
  @spec without(map(), non_neg_integer(), atom()) :: map()
  def without(%{channels: channels} = clip, node, path),
    do: %{clip | channels: Enum.reject(channels, &(&1.node == node and &1.path == path))}

  @doc "A sample that sets nothing."
  @spec empty() :: sample()
  def empty, do: %{translations: %{}, rotations: %{}, scales: %{}, weights: %{}}

  defp wrapped(time, duration, true) when duration > 0,
    do: time - Float.floor(time / duration) * duration

  defp wrapped(time, _duration, _loop), do: time

  defp merged(first, second, mix), do: Map.merge(first, second, fn _node, a, b -> mix.(a, b) end)

  defp value(%{times: times, values: values, interpolation: interpolation, path: path}, time) do
    last = tuple_size(times) - 1

    cond do
      last < 0 -> nil
      time <= elem(times, 0) -> plain(elem(values, 0), interpolation)
      time >= elem(times, last) -> plain(elem(values, last), interpolation)
      true -> between(times, values, interpolation, path, time)
    end
  end

  defp between(times, values, interpolation, path, time) do
    after_index = first_after(times, time, 1, tuple_size(times) - 1)
    before_index = after_index - 1
    start = elem(times, before_index)
    span = elem(times, after_index) - start
    fraction = (time - start) / span

    case interpolation do
      :step ->
        elem(values, before_index)

      :linear ->
        mix(path, elem(values, before_index), elem(values, after_index), fraction)

      :cubic ->
        {_in, from, out_tangent} = elem(values, before_index)
        {in_tangent, to, _out} = elem(values, after_index)
        hermite(path, from, out_tangent, to, in_tangent, fraction, span)
    end
  end

  defp first_after(times, _time, low, high) when low >= high, do: min(low, tuple_size(times) - 1)

  defp first_after(times, time, low, high) do
    middle = div(low + high, 2)

    if elem(times, middle) > time,
      do: first_after(times, time, low, middle),
      else: first_after(times, time, middle + 1, high)
  end

  defp plain({_in, value, _out}, :cubic), do: value
  defp plain(value, _interpolation), do: value

  defp mix(:rotation, from, to, fraction), do: Quat.slerp(from, to, fraction)
  defp mix(:weights, from, to, fraction), do: lerp_list(from, to, fraction)
  defp mix(_path, from, to, fraction), do: lerp(from, to, fraction)

  defp lerp({ax, ay, az}, {bx, by, bz}, amount),
    do: {ax + (bx - ax) * amount, ay + (by - ay) * amount, az + (bz - az) * amount}

  defp lerp_list(first, second, amount),
    do: Enum.zip_with(first, second, fn a, b -> a + (b - a) * amount end)

  defp hermite(path, from, out_tangent, to, in_tangent, fraction, span) do
    squared = fraction * fraction
    cubed = squared * fraction
    h00 = 2 * cubed - 3 * squared + 1
    h10 = cubed - 2 * squared + fraction
    h01 = -2 * cubed + 3 * squared
    h11 = cubed - squared

    combine(path, from, out_tangent, to, in_tangent, fn p0, m0, p1, m1 ->
      h00 * p0 + h10 * span * m0 + h01 * p1 + h11 * span * m1
    end)
  end

  defp combine(:rotation, {a, b, c, d}, {ma, mb, mc, md}, {e, f, g, h}, {na, nb, nc, nd}, curve) do
    Quat.normalize(
      {curve.(a, ma, e, na), curve.(b, mb, f, nb), curve.(c, mc, g, nc), curve.(d, md, h, nd)}
    )
  end

  defp combine(:weights, from, out_tangent, to, in_tangent, curve) do
    [from, out_tangent, to, in_tangent]
    |> Enum.zip()
    |> Enum.map(fn {p0, m0, p1, m1} -> curve.(p0, m0, p1, m1) end)
  end

  defp combine(_path, {a, b, c}, {ma, mb, mc}, {e, f, g}, {na, nb, nc}, curve),
    do: {curve.(a, ma, e, na), curve.(b, mb, f, nb), curve.(c, mc, g, nc)}
end
