defmodule Cauldron3D.Formats.Gltf.Materials do
  @moduledoc """
  A glTF document's materials as maps of plain values, in the metallic-roughness model.

  A material has `:name`, `:base_color` (`{r, g, b, a}`), `:metallic`, `:roughness`,
  `:emissive` (`{r, g, b}`), `:emissive_strength` (`KHR_materials_emissive_strength`),
  `:normal_scale`, `:occlusion_strength`, `:alpha_mode` (`:opaque`, `:mask` or `:blend`),
  `:alpha_cutoff`, `:double_sided`, `:unlit` (`KHR_materials_unlit`) and the textures
  `:base_texture`, `:metallic_roughness_texture`, `:normal_texture`, `:occlusion_texture`,
  `:emissive_texture`, each `nil` or a texture reference.

  A texture reference is `%{image: index, texcoord: set, wrap: {s, t}, filter: filter,
  transform: transform}`: `wrap` each `:repeat`, `:clamp` or `:mirror`, `filter` `:linear`
  or `:nearest` (the magnification filter), `transform` `nil` or
  `%{offset: {u, v}, scale: {u, v}, rotation: radians}` (`KHR_texture_transform`).
  """

  @wraps %{33_071 => :clamp, 33_648 => :mirror, 10_497 => :repeat}

  @doc "Every material of the document `json`, in its order."
  @spec read(map()) :: [map()]
  def read(json), do: json |> Map.get("materials", []) |> Enum.map(&material(json, &1))

  @doc "The material glTF uses for a primitive with none."
  @spec default() :: map()
  def default, do: material(%{}, %{})

  defp material(json, source) do
    pbr = Map.get(source, "pbrMetallicRoughness", %{})
    extensions = Map.get(source, "extensions", %{})
    [er, eg, eb] = Map.get(source, "emissiveFactor", [0, 0, 0])

    %{
      name: source["name"],
      base_color:
        pbr |> Map.get("baseColorFactor", [1, 1, 1, 1]) |> Enum.map(&(&1 / 1)) |> List.to_tuple(),
      base_texture: texture(json, pbr["baseColorTexture"]),
      metallic: Map.get(pbr, "metallicFactor", 1) / 1,
      roughness: Map.get(pbr, "roughnessFactor", 1) / 1,
      metallic_roughness_texture: texture(json, pbr["metallicRoughnessTexture"]),
      normal_texture: texture(json, source["normalTexture"]),
      normal_scale: Map.get(source["normalTexture"] || %{}, "scale", 1) / 1,
      occlusion_texture: texture(json, source["occlusionTexture"]),
      occlusion_strength: Map.get(source["occlusionTexture"] || %{}, "strength", 1) / 1,
      emissive: {er / 1, eg / 1, eb / 1},
      emissive_texture: texture(json, source["emissiveTexture"]),
      emissive_strength:
        Map.get(extensions["KHR_materials_emissive_strength"] || %{}, "emissiveStrength", 1) / 1,
      alpha_mode: alpha_mode(Map.get(source, "alphaMode", "OPAQUE")),
      alpha_cutoff: Map.get(source, "alphaCutoff", 0.5) / 1,
      double_sided: Map.get(source, "doubleSided", false),
      unlit: Map.has_key?(extensions, "KHR_materials_unlit")
    }
  end

  defp alpha_mode("MASK"), do: :mask
  defp alpha_mode("BLEND"), do: :blend
  defp alpha_mode(_opaque), do: :opaque

  defp texture(_json, nil), do: nil

  defp texture(json, info) do
    source = Enum.at(json["textures"], info["index"])
    sampler = if source["sampler"], do: Enum.at(json["samplers"], source["sampler"]), else: %{}

    %{
      image: image(source),
      texcoord: Map.get(info, "texCoord", 0),
      wrap: {wrap(sampler["wrapS"]), wrap(sampler["wrapT"])},
      filter: if(sampler["magFilter"] == 9728, do: :nearest, else: :linear),
      transform: transform(get_in(info, ["extensions", "KHR_texture_transform"]))
    }
  end

  defp image(%{"source" => index}) when is_integer(index), do: index

  defp image(%{"extensions" => extensions}) do
    Enum.find_value(Map.values(extensions), fn extension -> extension["source"] end)
  end

  defp wrap(nil), do: :repeat
  defp wrap(mode), do: Map.get(@wraps, mode, :repeat)

  defp transform(nil), do: nil

  defp transform(source) do
    [ou, ov] = Map.get(source, "offset", [0, 0])
    [su, sv] = Map.get(source, "scale", [1, 1])

    %{
      offset: {ou / 1, ov / 1},
      scale: {su / 1, sv / 1},
      rotation: Map.get(source, "rotation", 0) / 1
    }
  end
end
