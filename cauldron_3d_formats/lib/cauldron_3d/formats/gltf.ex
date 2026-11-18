defmodule Cauldron3D.Formats.Gltf do
  @moduledoc """
  glTF 2.0 documents, `.gltf` (JSON with its buffers and images beside it or inline as
  `data:` URIs) and `.glb` (the binary container).

      {:ok, sponza} = Cauldron3D.Formats.Gltf.read("Sponza/glTF/Sponza.gltf")
      length(sponza.meshes)

  A document has:

    * `meshes` — `%{name, primitives, weights, target_names}`, primitives as
      `Cauldron3D.Formats.Gltf.Primitives` reads them, `weights` the morph target weights the
      mesh starts with and `target_names` the targets' names when the file gives them
    * `materials` — as `Cauldron3D.Formats.Gltf.Materials` reads them
    * `images` — `%{name, mime, bytes}`, `bytes` the PNG or JPEG file as stored
    * `instances` — `%{mesh, node, skin, name, matrix}` for every node of the scene with a
      mesh, `matrix` its world matrix as 16 numbers, column after column, and `skin` the
      index of its skin or `nil`
    * `nodes` — every node as `Cauldron3D.Formats.Gltf.Nodes.tree/1` gives them
    * `skins` — `%{name, joints, inverse_binds, skeleton}`: the joint node indices in the
      order vertex `joints` count them, each joint's inverse bind matrix (16 numbers,
      column after column; identity when the file gives none) and the skeleton's root
      node or `nil`
    * `animations` — the clips, as `Cauldron3D.Formats.Gltf.Animations` reads them and
      `Cauldron3D.Formats.Gltf.Clip` plays them
    * `extensions` — the document's top-level `extensions` object as decoded JSON, for
      formats built on glTF such as VRM (`Cauldron3D.Formats.Vrm`)

  Coordinates are glTF's: metres, +Y up, texture rows from the top.
  """

  alias Cauldron3D.Formats.Gltf.{Accessor, Animations, Materials, Nodes, Primitives}

  @glb_json 0x4E4F534A
  @glb_bin 0x004E4942

  @type t :: %__MODULE__{
          meshes: [map()],
          materials: [map()],
          images: [map()],
          instances: [map()],
          nodes: [Nodes.tree_node()],
          skins: [map()],
          animations: [map()],
          extensions: map()
        }

  defstruct meshes: [],
            materials: [],
            images: [],
            instances: [],
            nodes: [],
            skins: [],
            animations: [],
            extensions: %{}

  @doc "The document at `path`, its other files read from the same folder."
  @spec read(Path.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    with {:ok, bytes} <- File.read(path), do: parse(bytes, base: Path.dirname(path))
  end

  @doc """
  The document in `bytes`, a `.gltf` file's JSON or a `.glb` file. `:base` is the folder
  its relative URIs are read from (default the current folder).
  """
  @spec parse(binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def parse(bytes, opts \\ []) do
    base = Keyword.get(opts, :base, ".")

    with {:ok, json, binary} <- container(bytes),
         {:ok, buffers} <- buffers(json, binary, base),
         {:ok, images} <- images(json, buffers, base) do
      {:ok,
       %__MODULE__{
         meshes: meshes(json, buffers),
         materials: Materials.read(json),
         images: images,
         instances: Nodes.placed(json),
         nodes: Nodes.tree(json),
         skins: skins(json, buffers),
         animations: Animations.read(json, buffers, morph_counts(json)),
         extensions: Map.get(json, "extensions", %{})
       }}
    end
  rescue
    error in [ArgumentError, MatchError, KeyError, FunctionClauseError] ->
      {:error, {:malformed, Exception.message(error)}}
  end

  defp container(<<"glTF", 2::little-32, _length::little-32, rest::binary>>),
    do: chunks(rest, nil, nil)

  defp container(<<"glTF", version::little-32, _rest::binary>>),
    do: {:error, {:glb_version, version}}

  defp container(json), do: with({:ok, decoded} <- JSON.decode(json), do: {:ok, decoded, nil})

  defp chunks(
         <<length::little-32, @glb_json::little-32, data::binary-size(length), rest::binary>>,
         _json,
         binary
       ),
       do: chunks(rest, data, binary)

  defp chunks(
         <<length::little-32, @glb_bin::little-32, data::binary-size(length), rest::binary>>,
         json,
         _binary
       ),
       do: chunks(rest, json, data)

  defp chunks(
         <<length::little-32, _type::little-32, _data::binary-size(length), rest::binary>>,
         json,
         binary
       ),
       do: chunks(rest, json, binary)

  defp chunks(_end, nil, _binary), do: {:error, :no_json_chunk}

  defp chunks(_end, json, binary),
    do: with({:ok, decoded} <- JSON.decode(json), do: {:ok, decoded, binary})

  defp buffers(json, binary, base) do
    json
    |> Map.get("buffers", [])
    |> Enum.reduce_while({:ok, []}, fn buffer, {:ok, loaded} ->
      case buffer_bytes(buffer, binary, base) do
        {:ok, bytes} -> {:cont, {:ok, [bytes | loaded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, loaded} -> {:ok, Enum.reverse(loaded)}
      error -> error
    end)
  end

  defp buffer_bytes(%{"uri" => uri}, _binary, base), do: uri_bytes(uri, base)
  defp buffer_bytes(_buffer, nil, _base), do: {:error, :missing_glb_binary}
  defp buffer_bytes(_buffer, binary, _base), do: {:ok, binary}

  defp uri_bytes("data:" <> data, _base) do
    case String.split(data, ";base64,", parts: 2) do
      [_mime, encoded] ->
        Base.decode64(encoded) |> ok_or({:bad_data_uri, String.slice(data, 0, 40)})

      _other ->
        {:error, {:bad_data_uri, String.slice(data, 0, 40)}}
    end
  end

  defp uri_bytes(uri, base) do
    path = Path.join(base, URI.decode(uri))

    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, {reason, path}}
    end
  end

  defp ok_or({:ok, value}, _error), do: {:ok, value}
  defp ok_or(:error, error), do: {:error, error}

  defp images(json, buffers, base) do
    json
    |> Map.get("images", [])
    |> Enum.reduce_while({:ok, []}, fn image, {:ok, loaded} ->
      case image_bytes(json, buffers, image, base) do
        {:ok, bytes} ->
          {:cont,
           {:ok, [%{name: image["name"], mime: mime(image, bytes), bytes: bytes} | loaded]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, loaded} -> {:ok, Enum.reverse(loaded)}
      error -> error
    end)
  end

  defp image_bytes(_json, _buffers, %{"uri" => uri}, base), do: uri_bytes(uri, base)

  defp image_bytes(json, buffers, %{"bufferView" => index}, _base) do
    view = Enum.at(json["bufferViews"], index)
    buffer = Enum.at(buffers, view["buffer"])
    {:ok, binary_part(buffer, Map.get(view, "byteOffset", 0), view["byteLength"])}
  end

  defp mime(%{"mimeType" => mime}, _bytes), do: mime
  defp mime(_image, <<137, "PNG", _rest::binary>>), do: "image/png"
  defp mime(_image, <<0xFF, 0xD8, _rest::binary>>), do: "image/jpeg"
  defp mime(_image, _bytes), do: "application/octet-stream"

  defp skins(json, buffers) do
    for skin <- Map.get(json, "skins", []) do
      joints = skin["joints"]

      %{
        name: skin["name"],
        joints: joints,
        inverse_binds: inverse_binds(json, buffers, skin["inverseBindMatrices"], length(joints)),
        skeleton: skin["skeleton"]
      }
    end
  end

  defp inverse_binds(_json, _buffers, nil, count), do: List.duplicate(Nodes.identity(), count)

  defp inverse_binds(json, buffers, accessor, _count) do
    {16, floats} = Accessor.floats(json, buffers, accessor)
    for <<matrix::binary-size(64) <- floats>>, do: matrix_tuple(matrix)
  end

  defp matrix_tuple(binary),
    do: List.to_tuple(for(<<value::little-float-32 <- binary>>, do: value))

  defp morph_counts(json) do
    meshes = Map.get(json, "meshes", [])

    for {%{"mesh" => mesh}, node} <- Enum.with_index(Map.get(json, "nodes", [])),
        count = meshes |> Enum.at(mesh) |> morph_count(),
        count > 0,
        into: %{},
        do: {node, count}
  end

  defp morph_count(mesh) do
    mesh
    |> Map.get("primitives", [])
    |> Enum.map(&length(Map.get(&1, "targets", [])))
    |> Enum.max(fn -> 0 end)
  end

  defp meshes(json, buffers) do
    json
    |> Map.get("meshes", [])
    |> Enum.with_index()
    |> Enum.map(fn {mesh, index} ->
      %{
        name: mesh["name"],
        primitives: Primitives.read(json, buffers, index),
        weights: Enum.map(Map.get(mesh, "weights", []), &(&1 / 1)),
        target_names: get_in(mesh, ["extras", "targetNames"]) || []
      }
    end)
  end
end
