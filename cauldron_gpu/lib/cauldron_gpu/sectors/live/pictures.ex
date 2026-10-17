if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Live.Pictures do
    @moduledoc """
    Pictures of a `Cauldron2D.Sectors.Pictures` set uploaded on first use, each through a
    light table: table `nil` shows the palette's own colours, table `n` each colour index
    first mapped through the set's table `n` (as a fixed light table draws it). Textures
    and materials are kept by `{picture, table}` and made once.

        pictures = CauldronGPU.Sectors.Live.Pictures.new(set, palette)
        {%{handle: handle, masked: false}, pictures} = CauldronGPU.Sectors.Live.Pictures.texture(pictures, target, 7, nil)
        {material, pictures} = CauldronGPU.Sectors.Live.Pictures.material(pictures, target, {:wall, 7, nil}, fn texture -> %CauldronGPU.Material{base_texture: texture.handle} end)

    The set must keep its pictures in Elixir (`Pictures.new(named, tables, native: false)`);
    `palette` is 768 bytes.
    """

    alias Cauldron2D.Sectors.Pictures, as: Set
    alias CauldronGPU.{Handle, Material, Target}
    alias CauldronGPU.Sectors.Textures

    @type texture :: %{handle: Handle.t(), masked: boolean()}
    @type t :: %__MODULE__{
            set: Set.t(),
            palette: binary(),
            colours: %{(non_neg_integer() | nil) => tuple()},
            textures: %{{non_neg_integer(), non_neg_integer() | nil} => texture()},
            materials: %{term() => Handle.t()}
          }

    @enforce_keys [:set, :palette]
    defstruct [:set, :palette, colours: %{}, textures: %{}, materials: %{}]

    @doc "No pictures uploaded yet from `set`, coloured by `palette`."
    @spec new(Set.t(), binary()) :: t()
    def new(%Set{pictures: pictures} = set, palette) when is_tuple(pictures),
      do: %__MODULE__{set: set, palette: palette}

    def new(%Set{}, _palette) do
      raise ArgumentError, "the pictures must be kept in Elixir: Pictures.new(..., native: false)"
    end

    @doc "The texture of `picture` through light table `table`, uploaded through `target` the first time."
    @spec texture(t(), Target.t(), non_neg_integer(), non_neg_integer() | nil) :: {texture(), t()}
    def texture(%__MODULE__{} = pictures, target, picture, table) do
      case Map.fetch(pictures.textures, {picture, table}) do
        {:ok, texture} -> {texture, pictures}
        :error -> upload(pictures, target, picture, table)
      end
    end

    @doc """
    The material kept as `key`, made the first time from `make`, given the texture of
    `key`'s picture through its table: `key` is a tuple whose second and third elements
    are the picture and the table.
    """
    @spec material(t(), Target.t(), tuple(), (texture() -> Material.t())) :: {Handle.t(), t()}
    def material(%__MODULE__{} = pictures, target, key, make) do
      case Map.fetch(pictures.materials, key) do
        {:ok, handle} ->
          {handle, pictures}

        :error ->
          {texture, pictures} = texture(pictures, target, elem(key, 1), elem(key, 2))
          handle = Target.material(target, make.(texture))
          {handle, %{pictures | materials: Map.put(pictures.materials, key, handle)}}
      end
    end

    @doc "Every handle uploaded."
    @spec handles(t()) :: [Handle.t()]
    def handles(%__MODULE__{} = pictures),
      do: Map.values(pictures.materials) ++ Enum.map(Map.values(pictures.textures), & &1.handle)

    @doc "The palette's colours through light table `table` (`nil` for none), as a tuple of 256 RGBA binaries."
    @spec colours(t(), non_neg_integer() | nil) :: {tuple(), t()}
    def colours(pictures, table) do
      case Map.fetch(pictures.colours, table) do
        {:ok, colours} ->
          {colours, pictures}

        :error ->
          colours = table_colours(pictures.palette, pictures.set.tables, table)
          {colours, %{pictures | colours: Map.put(pictures.colours, table, colours)}}
      end
    end

    defp upload(pictures, target, picture, table) do
      {colours, pictures} = colours(pictures, table)
      source = elem(pictures.set.pictures, picture)
      texture = %{Textures.texture(source, colours) | filter: :nearest}
      entry = %{handle: Target.texture(target, texture), masked: Map.get(source, :mask) != nil}
      {entry, %{pictures | textures: Map.put(pictures.textures, {picture, table}, entry)}}
    end

    defp table_colours(palette, _tables, nil),
      do: for(<<r, g, b <- palette>>, do: <<r, g, b, 255>>) |> List.to_tuple()

    defp table_colours(palette, tables, table) do
      plain = table_colours(palette, tables, nil)

      tables
      |> binary_part(table * 256, 256)
      |> :binary.bin_to_list()
      |> Enum.map(&elem(plain, &1))
      |> List.to_tuple()
    end
  end
end
