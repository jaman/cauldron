defmodule Cauldron3D.Formats.Gltf.Animations do
  @moduledoc """
  A glTF document's animation clips, as `Cauldron3D.Formats.Gltf.Clip` plays them.

  `read/2` gives one map for each clip:

    * `name` — the clip's name, or `nil`
    * `duration` — the last keyframe time of any channel, in seconds
    * `channels` — `%{node, path, interpolation, times, values}`: the node index the
      channel moves, `path` one of `:translation`, `:rotation`, `:scale` or `:weights`,
      `interpolation` one of `:linear`, `:step` or `:cubic`, `times` a tuple of keyframe
      times and `values` a tuple holding each keyframe's value. A translation or scale is
      `{x, y, z}`, a rotation `{x, y, z, w}` and weights a list of floats. A `:cubic`
      channel's keyframes are `{in_tangent, value, out_tangent}`.

  Channels that name no node, or a path other than the four above, are left out.

      {:ok, document} = Cauldron3D.Formats.Gltf.read("hero.glb")
      [%{name: "Walk", duration: 1.2}] = document.animations
  """

  alias Cauldron3D.Formats.Gltf.Accessor

  @paths %{
    "translation" => :translation,
    "rotation" => :rotation,
    "scale" => :scale,
    "weights" => :weights
  }

  @interpolations %{"LINEAR" => :linear, "STEP" => :step, "CUBICSPLINE" => :cubic}

  @doc "Every animation of `json`, reading from `buffers`; `targets` is each mesh node's morph target count."
  @spec read(map(), [binary()], %{non_neg_integer() => non_neg_integer()}) :: [map()]
  def read(json, buffers, targets) do
    for animation <- Map.get(json, "animations", []) do
      channels =
        for channel <- Map.get(animation, "channels", []),
            path = Map.get(@paths, get_in(channel, ["target", "path"])),
            node = get_in(channel, ["target", "node"]),
            node != nil do
          sampler = Enum.at(animation["samplers"], channel["sampler"])
          channel(json, buffers, node, path, sampler, Map.get(targets, node, 0))
        end

      %{name: animation["name"], duration: duration(channels), channels: channels}
    end
  end

  defp channel(json, buffers, node, path, sampler, target_count) do
    interpolation = Map.get(@interpolations, sampler["interpolation"], :linear)
    {1, times} = Accessor.floats(json, buffers, sampler["input"])
    {width, values} = Accessor.floats(json, buffers, sampler["output"])
    times = for <<time::little-float-32 <- times>>, do: time

    %{
      node: node,
      path: path,
      interpolation: interpolation,
      times: List.to_tuple(times),
      values: values |> elements(path, width, target_count, length(times), interpolation)
    }
  end

  defp elements(values, path, width, target_count, keyframes, interpolation) do
    per_keyframe = if interpolation == :cubic, do: 3, else: 1

    size =
      if path == :weights,
        do: weights_size(values, target_count, keyframes, per_keyframe),
        else: width

    floats = for <<value::little-float-32 <- values>>, do: value

    floats
    |> Enum.chunk_every(size)
    |> Enum.map(&shaped(&1, path))
    |> Enum.chunk_every(per_keyframe)
    |> Enum.map(&keyframe(&1, interpolation))
    |> List.to_tuple()
  end

  defp weights_size(_values, target_count, _keyframes, _per_keyframe) when target_count > 0,
    do: target_count

  defp weights_size(values, _target_count, keyframes, per_keyframe),
    do: div(div(byte_size(values), 4), max(keyframes * per_keyframe, 1))

  defp shaped([x, y, z], path) when path in [:translation, :scale], do: {x, y, z}
  defp shaped([x, y, z, w], :rotation), do: {x, y, z, w}
  defp shaped(weights, :weights), do: weights

  defp keyframe([in_tangent, value, out_tangent], :cubic), do: {in_tangent, value, out_tangent}
  defp keyframe([value], _interpolation), do: value

  defp duration([]), do: 0.0

  defp duration(channels) do
    channels
    |> Enum.map(fn %{times: times} ->
      if tuple_size(times) == 0, do: 0.0, else: elem(times, tuple_size(times) - 1)
    end)
    |> Enum.max()
  end
end
