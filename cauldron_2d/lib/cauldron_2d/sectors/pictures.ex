defmodule Cauldron2D.Sectors.Pictures do
  @moduledoc """
  The pictures a sector view draws from — wall textures, floor textures, sprites — and the
  light tables that darken them, held ready for `Cauldron2D.Sectors.Frame`.

      pictures =
        Cauldron2D.Sectors.Pictures.new(
          [{"STARTAN3", %{width: 128, height: 128, pixels: columns, mask: nil}}, ...],
          Cauldron2D.Sectors.Light.tables(palette)
        )

      Cauldron2D.Sectors.Pictures.id(pictures, "STARTAN3")

  A picture is indexed colour stored **column by column**: `pixels` holds `height` bytes
  for column 0, then column 1, and so on, `width * height` bytes in all. `mask` is `nil`
  for a picture with no holes, or as many bytes as `pixels` with `0` where the picture is
  transparent. Every picture is addressed by its position in the list given to `new/2`,
  which `id/2` looks up by name.

  `tables` is the light tables: 256 bytes each, a colour index in, the colour to draw out.
  Table `0` draws a picture as it is. How many there are and what each does is the
  caller's; `Cauldron2D.Sectors.Light` builds a ramp from a palette.

  Where the NIF loaded, the pictures are copied into it once, and a set may be shared
  between processes and drawn from by any number of frames.
  """

  alias Cauldron2D.Sectors.Frame

  @enforce_keys [:names, :sizes, :tables, :maps]
  defstruct [:names, :sizes, :tables, :maps, :native, :pictures]

  @type picture :: %{
          required(:width) => pos_integer(),
          required(:height) => pos_integer(),
          required(:pixels) => binary(),
          optional(:mask) => binary() | nil
        }

  @type t :: %__MODULE__{
          names: %{term() => non_neg_integer()},
          sizes: tuple(),
          tables: binary(),
          maps: pos_integer(),
          native: reference() | nil,
          pictures: tuple() | nil
        }

  @doc """
  A set of `named` pictures, `[{name, picture}]`, with the light `tables`.

  `native: false` keeps them in Elixir even where the NIF loaded. Raises `ArgumentError`
  for a picture whose bytes do not match its size, or tables that are not whole tables.
  """
  @spec new([{term(), picture()}], binary(), keyword()) :: t()
  def new(named, tables, opts \\ []) when is_list(named) and is_binary(tables) do
    if tables == <<>> or rem(byte_size(tables), 256) != 0,
      do: raise(ArgumentError, "light tables must be whole 256-byte tables")

    pictures = Enum.map(named, fn {name, picture} -> checked(name, picture) end)
    native? = Keyword.get(opts, :native, true) and Frame.available?()

    %__MODULE__{
      names: named |> Enum.with_index() |> Map.new(fn {{name, _picture}, id} -> {name, id} end),
      sizes: pictures |> Enum.map(&{&1.width, &1.height}) |> List.to_tuple(),
      tables: tables,
      maps: div(byte_size(tables), 256),
      native: if(native?, do: Frame.native_set(Enum.map(pictures, &packed/1), tables)),
      pictures: if(native?, do: nil, else: List.to_tuple(pictures))
    }
  end

  @doc "The id of the picture called `name`, or `nil`."
  @spec id(t(), term()) :: non_neg_integer() | nil
  def id(%__MODULE__{names: names}, name), do: Map.get(names, name)

  @doc "The `{width, height}` of picture `id`."
  @spec size(t(), non_neg_integer()) :: {pos_integer(), pos_integer()}
  def size(%__MODULE__{sizes: sizes}, id), do: elem(sizes, id)

  @doc "How many pictures the set holds."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{sizes: sizes}), do: tuple_size(sizes)

  @doc """
  A picture from rows: `rows` is `width * height` bytes, row by row, as most images are
  stored; `mask_rows` likewise or `nil`. Gives the column-by-column picture `new/2` takes.
  """
  @spec from_rows(pos_integer(), pos_integer(), binary(), binary() | nil) :: picture()
  def from_rows(width, height, rows, mask_rows \\ nil) do
    %{
      width: width,
      height: height,
      pixels: transpose(rows, width, height),
      mask: mask_rows && transpose(mask_rows, width, height)
    }
  end

  defp transpose(rows, width, height) do
    for x <- 0..(width - 1)//1,
        y <- 0..(height - 1)//1,
        into: <<>>,
        do: <<:binary.at(rows, y * width + x)>>
  end

  defp checked(name, %{width: width, height: height, pixels: pixels} = picture)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    mask = Map.get(picture, :mask)

    cond do
      byte_size(pixels) != width * height ->
        raise ArgumentError,
              "picture #{inspect(name)} has #{byte_size(pixels)} bytes for #{width}x#{height}"

      mask != nil and byte_size(mask) != width * height ->
        raise ArgumentError, "picture #{inspect(name)} has a mask of the wrong size"

      true ->
        %{width: width, height: height, pixels: pixels, mask: mask}
    end
  end

  defp packed(picture), do: {picture.width, picture.height, picture.pixels, picture.mask || :none}
end
