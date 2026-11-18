if Code.ensure_loaded?(Cauldron3D.Render) do
  defmodule Cauldron3D.Scene.Software.Resources do
    @moduledoc """
    The meshes, textures and materials a `Cauldron3D.Scene.Software` renderer holds, in
    the shapes it draws with: a mesh as tuples of vertices (`{position, normal, uv}`),
    skin weights, colours and morph target offsets, with its triangles grouped by part; a texture as a
    `Cauldron3D.Texture` in RGBA; a material as sent.

    A texture that holds a PNG or JPEG file is decoded with the `decode` function given to
    `new/1`; one that cannot be decoded is `nil`, and surfaces using it show their base
    colour. A `:rgba16f` texture is `nil` as well.
    """

    alias Cauldron3D.Scene.{Canvas, Material, Mesh, Texture}

    @type vertex :: {{float(), float(), float()}, {float(), float(), float()}, {float(), float()}}
    @type mesh :: %{
            vertices: tuple(),
            parts: [[{non_neg_integer(), non_neg_integer(), non_neg_integer()}]],
            skin: tuple() | nil,
            colors: tuple() | nil,
            morphs: [%{positions: tuple(), normals: tuple() | nil}]
          }
    @type decode :: (Texture.t() -> {:ok, Texture.t()} | {:error, term()})
    @type t :: %__MODULE__{
            meshes: %{pos_integer() => mesh()},
            textures: %{pos_integer() => Cauldron3D.Texture.t() | nil},
            materials: %{pos_integer() => Material.t()},
            decode: decode()
          }

    defstruct meshes: %{}, textures: %{}, materials: %{}, decode: nil

    @doc "No resources yet; `decode` turns an encoded texture into RGBA."
    @spec new(decode()) :: t()
    def new(decode), do: %__MODULE__{decode: decode}

    @doc "The resources after one change; changes that are not uploads or drops leave them as they are."
    @spec change(t(), term()) :: t()
    def change(resources, {:mesh, id, %Mesh{} = mesh}),
      do: put_in(resources.meshes[id], decoded_mesh(mesh))

    def change(resources, {:texture, id, %Texture{} = texture}),
      do: put_in(resources.textures[id], picture(texture, resources.decode))

    def change(resources, {:canvas, id, %Canvas{width: width, height: height}}),
      do:
        put_in(
          resources.textures[id],
          Cauldron3D.Texture.rgba(width, height, :binary.copy(<<0, 0, 0, 0>>, width * height))
        )

    def change(resources, {:material, id, %Material{} = material}),
      do: put_in(resources.materials[id], material)

    def change(resources, {:drop_mesh, id}),
      do: %{resources | meshes: Map.delete(resources.meshes, id)}

    def change(resources, {:drop_texture, id}),
      do: %{resources | textures: Map.delete(resources.textures, id)}

    def change(resources, {:drop_material, id}),
      do: %{resources | materials: Map.delete(resources.materials, id)}

    def change(resources, _change), do: resources

    @doc "The resources the scene `record` still holds (`Cauldron3D.Scene.Host.Record`): the others are dropped."
    @spec kept(t(), Cauldron3D.Scene.Host.Record.t()) :: t()
    def kept(resources, %Cauldron3D.Scene.Host.Record{resources: held}) do
      %{
        resources
        | meshes: Map.filter(resources.meshes, fn {id, _} -> Map.has_key?(held, {:mesh, id}) end),
          textures:
            Map.filter(resources.textures, fn {id, _} -> Map.has_key?(held, {:texture, id}) end),
          materials:
            Map.filter(resources.materials, fn {id, _} -> Map.has_key?(held, {:material, id}) end)
      }
    end

    @doc "A mesh as `Cauldron3D.Scene.Software` draws it."
    @spec decoded_mesh(Mesh.t()) :: mesh()
    def decoded_mesh(%Mesh{} = mesh) do
      indices = for <<index::little-unsigned-32 <- mesh.indices>>, do: index
      count = length(indices)
      parts = if mesh.parts == [], do: [{0, count}], else: mesh.parts

      %{
        vertices: vertices(mesh.vertices),
        parts: Enum.map(parts, &triangles(indices, &1)),
        skin: skin(mesh.skin),
        colors: colors(mesh.colors),
        morphs: Enum.map(mesh.morphs, &morph/1)
      }
    end

    defp vertices(binary) do
      vertices =
        for <<x::little-float-32, y::little-float-32, z::little-float-32, u::little-float-32,
              nx::little-float-32, ny::little-float-32, nz::little-float-32, v::little-float-32,
              _rest::binary-size(16) <- binary>>,
            do: {{x, y, z}, {nx, ny, nz}, {u, v}}

      List.to_tuple(vertices)
    end

    defp triangles(indices, {first, count}) do
      indices
      |> Enum.slice(first, count)
      |> Enum.chunk_every(3, 3, :discard)
      |> Enum.map(&List.to_tuple/1)
    end

    defp morph(%{positions: positions, normals: normals}),
      do: %{positions: offsets(positions), normals: offsets(normals)}

    defp offsets(nil), do: nil

    defp offsets(binary),
      do: List.to_tuple(for <<x::little-float-32, y::little-float-32, z::little-float-32 <- binary>>, do: {x, y, z})

    defp skin(nil), do: nil

    defp skin(binary),
      do:
        List.to_tuple(
          for <<b0, b1, b2, b3, w0, w1, w2, w3 <- binary>>,
            do: {{b0, b1, b2, b3}, {w0, w1, w2, w3}}
        )

    defp colors(nil), do: nil

    defp colors(binary),
      do: List.to_tuple(for <<r, g, b, a <- binary>>, do: {r / 255, g / 255, b / 255, a / 255})

    defp picture(%Texture{encoding: :raw, format: format} = texture, _decode)
         when format in [:srgb, :linear],
         do: Cauldron3D.Texture.rgba(texture.width, texture.height, texture.pixels)

    defp picture(%Texture{encoding: :raw}, _decode), do: nil

    defp picture(%Texture{} = texture, decode) when is_function(decode, 1) do
      case decode.(texture) do
        {:ok, %Texture{encoding: :raw} = decoded} -> picture(decoded, nil)
        _undecoded -> nil
      end
    end

    defp picture(%Texture{}, nil), do: nil
  end
end
