defmodule Cauldron2D.Picture do
  @moduledoc """
  Pictures for a 2D game's art, written in code or read from files, and the changes art needs: frames cut from a strip, flips, turns, tints, scaling.

  Pictures written in code: a sprite as text with a palette, a shape as an outline, and
  the derivations a game needs — headings, recolouring, tinting, scaling, flipping,
  turning, cutting into frames, strips; and the same read from `.png` and `.pic` files.

  Every function is pure and returns a `Cauldron2D.Raster`.

      ship = Cauldron2D.Picture.sprite(\"\"\"
      ..RR..
      .RWWR.
      RRWWRR
      \"\"\", R: "#c33", W: :white)

      headings = Cauldron2D.Picture.headings([{15, 0}, {-8, 8}, {-8, -8}], 64, size: {16, 16}, fill: :white)
      team_ship = Cauldron2D.Picture.recolour(ship, %{{204, 51, 51, 255} => {51, 51, 204, 255}})

  ## Colours

  A colour in a palette or an option is `"#rgb"`, `"#rrggbb"`, `"#rrggbbaa"`, a colour
  name (`Cauldron2D.Palette`), or an `{r, g, b}` or `{r, g, b, a}` tuple. `.` and space
  in a picture are transparent.

  ## Shapes

  An outline is a list of `{x, y}` points with `x` to the right and `y` upward, closed
  from the last point back to the first. Heading `0` is the shape as written, pointing
  right; headings turn counter-clockwise on screen.
  """

  @type color_spec() :: Linocut.color_spec()
  @type point() :: Linocut.point()

  @doc """
  The raster mirrored left to right (`:horizontal`) or top to bottom (`:vertical`).
  """
  @spec flip(Cauldron2D.Raster.t(), :horizontal | :vertical) :: Cauldron2D.Raster.t()
  def flip(raster, axis), do: Linocut.flip(raster, axis)

  @doc """
  The raster cut into frames `{width, height}` pixels each, left to right then top to
  bottom. A remainder narrower or shorter than a frame is left out.
  """
  @spec frames(
          Cauldron2D.Raster.t(),
          {pos_integer(), pos_integer()}
        ) :: [Cauldron2D.Raster.t()]
  def frames(raster, size), do: Linocut.frames(raster, size)

  @doc """
  The shape at each of `count` headings, heading `0` first.

  Takes the options of `outline/2`; `:rotate` is added to each heading's turn.
  """
  @spec headings([point()], pos_integer(), keyword()) :: [Cauldron2D.Raster.t()]
  def headings(points, count, opts), do: Linocut.headings(points, count, opts)

  @doc """
  The picture in a file, by its extension: a `.png`, or a `.pic` (the text form `pic/2`
  reads) with `opts` as `sprite/3` takes them.
  """
  @spec load(
          Path.t(),
          keyword()
        ) :: {:ok, Cauldron2D.Raster.t()} | {:error, term()}
  def load(path, opts \\ []), do: Linocut.load(path, opts)

  @doc """
  A shape drawn from its outline.

  ## Options

    * `:size` — `{width, height}` of the raster. Required
    * `:fill` — the colour inside. Default: none
    * `:stroke` — the colour of the outline. Default: the fill
    * `:scale` — pixels per shape unit. Default: whatever fits the shape's farthest point
      inside the raster with a one-pixel margin
    * `:rotate` — radians to turn the shape counter-clockwise on screen. Default `0`
  """
  @spec outline(
          [point()],
          keyword()
        ) :: Cauldron2D.Raster.t()
  def outline(points, opts), do: Linocut.outline(points, opts)

  @doc """
  A picture in the `.pic` text form, a sprite as text with its palette in the same file.
  """
  @spec pic(
          String.t(),
          keyword()
        ) :: {:ok, Cauldron2D.Raster.t()} | {:error, term()}
  def pic(text, opts \\ []), do: Linocut.pic(text, opts)

  @doc """
  Every pixel passed through `mapping`: a map from colour to colour, or a function of a colour.
  """
  @spec recolour(
          Cauldron2D.Raster.t(),
          %{required(Cauldron2D.Raster.color()) => color_spec()}
          | (Cauldron2D.Raster.color() -> Cauldron2D.Raster.color())
        ) :: Cauldron2D.Raster.t()
  def recolour(raster, mapping), do: Linocut.recolour(raster, mapping)

  @doc """
  The raster turned `degrees` counter-clockwise on screen, a multiple of 90.
  """
  @spec rotate(Cauldron2D.Raster.t(), integer()) :: Cauldron2D.Raster.t()
  def rotate(raster, degrees), do: Linocut.rotate(raster, degrees)

  @doc """
  The raster enlarged `factor` times, each pixel becoming a square block.
  """
  @spec scale(Cauldron2D.Raster.t(), pos_integer()) :: Cauldron2D.Raster.t()
  def scale(raster, factor), do: Linocut.scale(raster, factor)

  @doc """
  A sprite from a picture and a palette.

  ## Options

    * `:size` — `{width, height}` of the raster, with the picture centred in it. Default:
      the picture's own size
    * `:background` — the colour of `.` and space. Default: transparent
  """
  @spec sprite(String.t(), keyword() | map(), keyword()) :: Cauldron2D.Raster.t()
  def sprite(picture, palette, opts \\ []), do: Linocut.sprite(picture, palette, opts)

  @doc """
  The picture scaled to a share of its size on each axis and placed back in a canvas of
  the original size.

  ## Options

    * `:anchor` — `:centre` (default) or `:bottom`, where the scaled picture sits
    * `:lean` — `-1.0..1.0`, how far toward an edge it slides across. Default `0.0`
  """
  @spec squash(Cauldron2D.Raster.t(), {number(), number()}, keyword()) :: Cauldron2D.Raster.t()
  def squash(raster, factors, opts \\ []), do: Linocut.squash(raster, factors, opts)

  @doc """
  Every opaque pixel mixed `amount` (0.0 to 1.0) of the way toward `colour`; transparent ones untouched.
  """
  @spec tint(Cauldron2D.Raster.t(), color_spec(), number()) :: Cauldron2D.Raster.t()
  def tint(raster, colour, amount), do: Linocut.tint(raster, colour, amount)

  @doc """
  A raster of `size` with every pixel of `raster` put where `fun` sends its position.

  A pixel sent outside the new raster is dropped; a position nothing is sent to keeps
  the background.
  """
  @spec transform(Cauldron2D.Raster.t(), {pos_integer(), pos_integer()}, (point() -> point())) ::
          Cauldron2D.Raster.t()
  def transform(raster, size, fun), do: Linocut.transform(raster, size, fun)

  @doc """
  The picture in PNG `bytes`, or why it could not be read.
  """
  @spec decode_png(binary()) :: {:ok, Cauldron2D.Raster.t()} | {:error, term()}
  def decode_png(bytes), do: Linocut.Png.decode(bytes)
end
