defmodule Greenware.UI do
  @moduledoc "The hand-drawn interface: clay panels, typewritten text, and the menus."

  alias Cauldron.Menu
  alias Greenware.{Canvas, Fonts, Palette}

  @ink Palette.c(:ink)
  @bone Palette.c(:bone)
  @paper Palette.c(:paper)
  @parchment Palette.c(:parchment)
  @amber Palette.c(:amber)
  @gold Palette.c(:gold)
  @ember Palette.c(:ember)

  def ink, do: @ink
  def bone, do: @bone
  def paper, do: @paper
  def amber, do: @amber
  def gold, do: @gold
  def ember, do: @ember

  @doc "A clay slab with a shadow, a lighter top edge and a dark border."
  def panel(canvas, {x, y, width, height}, opts \\ []) do
    colour = Keyword.get(opts, :colour, {54, 38, 30, 244})
    border = Keyword.get(opts, :border, {24, 17, 14, 255})
    alpha = Keyword.get(opts, :alpha, 1.0)

    canvas
    |> Canvas.rect({x + 3, y + 4}, {width, height}, Palette.a(:soot, 0.45 * alpha))
    |> Canvas.rect({x, y}, {width, height}, put_alpha(colour, alpha))
    |> Canvas.rect({x, y}, {width, 2}, Palette.a(:parchment, 0.22 * alpha))
    |> Canvas.rect({x + 1, y + height - 2}, {width - 2, 1}, Palette.a(:soot, 0.5 * alpha))
    |> Canvas.box({x, y}, {width, height}, border, alpha: alpha)
  end

  def button(canvas, rect, label, opts \\ []) do
    focused? = Keyword.get(opts, :focused?, false)
    colour = if focused?, do: {86, 55, 37, 255}, else: {47, 34, 28, 255}
    text_colour = if focused?, do: @gold, else: @parchment

    canvas
    |> panel(rect, colour: colour, border: if(focused?, do: @amber, else: {23, 16, 13, 255}))
    |> label(label, rect, colour: text_colour, align: :centre)
  end

  @doc "Text centred or left in a rectangle."
  def label(canvas, text, {x, y, width, height}, opts \\ []) do
    font = Keyword.get(opts, :font, Fonts.body())
    colour = Keyword.get(opts, :colour, @bone)
    align = Keyword.get(opts, :align, :left)
    text = text || ""

    width_px =
      if font == Fonts.display(), do: Fonts.display_width(text), else: Fonts.body_width(text)

    left = if align == :centre, do: x + div(width - width_px, 2), else: x
    top = if Keyword.get(opts, :middle, false), do: y + div(height - 20, 2), else: y
    Canvas.text(canvas, font, text, {left, top}, colour: colour, wrap: width, align: align)
  end

  @doc "A heading in the display face, or the body face when it is too long."
  def heading(canvas, text, {x, y}, opts \\ []) do
    font = if Fonts.display_width(text) > 560, do: Fonts.body(), else: Fonts.display()
    colour = Keyword.get(opts, :colour, @gold)
    Canvas.text(canvas, font, text, {x, y}, colour: colour, shadow: Palette.a(:soot, 0.7))
  end

  @doc "A horizontal meter."
  def meter(canvas, {x, y, width, height}, fraction, colour, opts \\ []) do
    fraction = fraction |> max(0.0) |> min(1.0)

    canvas
    |> Canvas.rect({x, y}, {width, height}, {22, 16, 13, 255})
    |> Canvas.rect({x + 1, y + 1}, {max(1, round((width - 2) * fraction)), height - 2}, colour)
    |> Canvas.box({x, y}, {width, height}, {13, 9, 7, 255})
    |> then(fn c ->
      if Keyword.get(opts, :label, true) do
        Canvas.text(c, Fonts.body(), Keyword.get(opts, :text, ""), {x + 3, y - 1}, colour: @ink)
      else
        c
      end
    end)
  end

  @doc "A small dashed box, for a point of interest."
  def dashed(canvas, {x, y, width, height}, colour, alpha \\ 0.9) do
    colour = put_alpha(colour, alpha)

    Enum.reduce(0..div(width, 10), canvas, fn index, c ->
      x1 = x + index * 10
      Canvas.line(c, {x1, y}, {min(x + width, x1 + 5), y}, colour)
      Canvas.line(c, {x1, y + height}, {min(x + width, x1 + 5), y + height}, colour)
    end)
    |> then(fn c ->
      Enum.reduce(0..div(height, 10), c, fn index, c ->
        y1 = y + index * 10
        Canvas.line(c, {x, y1}, {x, min(y + height, y1 + 5)}, colour)
        Canvas.line(c, {x + width, y1}, {x + width, min(y + height, y1 + 5)}, colour)
      end)
    end)
  end

  @doc "A focus ring around a card."
  def focus_ring(canvas, {x, y, width, height}, colour) do
    canvas
    |> Canvas.box({x - 3, y - 3}, {width + 6, height + 6}, put_alpha(colour, 0.35), thickness: 3)
    |> Canvas.box({x - 1, y - 1}, {width + 2, height + 2}, colour, thickness: 1)
  end

  @doc "A dialogue panel: speaker, wrapped line, and a prompt."
  def dialogue(canvas, rect, speaker, text, opts \\ []) do
    show_prompt? = Keyword.get(opts, :prompt?, true)

    canvas
    |> panel(rect, colour: {42, 30, 24, 246})
    |> then(fn c ->
      if speaker do
        Canvas.text(
          c,
          Fonts.body(),
          String.upcase(speaker),
          {elem(rect, 0) + 14, elem(rect, 1) + 10},
          colour: @amber
        )
      else
        c
      end
    end)
    |> Canvas.text(Fonts.body(), text, {elem(rect, 0) + 14, elem(rect, 1) + 34},
      colour: @paper,
      wrap: elem(rect, 2) - 28
    )
    |> then(fn c ->
      if show_prompt? do
        Canvas.text(
          c,
          Fonts.body(),
          ">",
          {elem(rect, 0) + elem(rect, 2) - 24, elem(rect, 1) + elem(rect, 3) - 22},
          colour: @gold
        )
      else
        c
      end
    end)
  end

  @doc "A menu drawn from a `Cauldron.Menu`, with its title and rows."
  def menu(canvas, menu, at, width, opts \\ [])

  def menu(canvas, menu, {x, y, _width, _height}, width, opts),
    do: menu(canvas, menu, {x, y}, width, opts)

  def menu(canvas, %Menu{} = menu, {x, y}, width, opts) do
    title = Menu.title(menu)
    {_first, rows} = Menu.window(menu, Keyword.get(opts, :rows, 6))
    line = Keyword.get(opts, :line, 22)
    height = 18 + max(1, length(rows)) * line + 16

    canvas = panel(canvas, {x, y, width, height}, colour: {44, 31, 24, 246})

    canvas =
      if title != "" do
        Canvas.text(canvas, Fonts.body(), String.upcase(title), {x + 12, y + 8}, colour: @amber)
      else
        canvas
      end

    canvas =
      Enum.reduce(Enum.with_index(rows), canvas, fn {row, index}, c ->
        ry = y + 30 + index * line

        case row.kind do
          :gap ->
            c

          :note ->
            Canvas.text(c, Fonts.body(), row.label, {x + 12, ry}, colour: Palette.c(:parchment))

          _ ->
            c =
              if row.focused?,
                do: Canvas.rect(c, {x + 5, ry - 2}, {width - 10, line - 2}, {83, 53, 36, 255}),
                else: c

            colour = if row.focused?, do: @gold, else: @bone
            c = Canvas.text(c, Fonts.body(), row.label, {x + 12, ry}, colour: colour)

            c =
              if row.value,
                do:
                  Canvas.text(
                    c,
                    Fonts.body(),
                    row.value,
                    {x + width - 12 - Fonts.body_width(row.value), ry},
                    colour: @parchment
                  ),
                else: c

            if row.fraction do
              Canvas.rect(c, {x + width - 78, ry + 7}, {66, 4}, {27, 20, 16, 255})
              |> Canvas.rect({x + width - 78, ry + 7}, {round(66 * row.fraction), 4}, @amber)
            else
              c
            end
        end
      end)

    case Menu.prompt(menu) do
      nil ->
        canvas

      prompt ->
        Canvas.text(canvas, Fonts.body(), String.upcase(prompt.text), {x + 12, y + height - 18},
          colour: @gold
        )
    end
  end

  @doc "The speaker's name."
  def speaker(:greenware), do: "GREENWARE"
  def speaker(:cat), do: "THE CAT"
  def speaker(:green_man), do: "THE GREEN MAN"
  def speaker(:boy), do: "THE BOY"
  def speaker(:choir), do: "THE CHOIR"
  def speaker(:potter), do: "THE POTTER"
  def speaker(:narrator), do: nil
  def speaker(_), do: nil

  @doc "A short label for an act."
  def act_label(act), do: "ACT #{act}"

  defp put_alpha({r, g, b, a}, alpha), do: {r, g, b, round(a * alpha)}
  defp put_alpha({r, g, b}, alpha), do: {r, g, b, round(255 * alpha)}
end
