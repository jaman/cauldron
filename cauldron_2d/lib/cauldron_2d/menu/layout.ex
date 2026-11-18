defmodule Cauldron2D.Menu.Layout do
  @moduledoc """
  A `Cauldron.Menu` laid out as `Cauldron2D.Screen` items, in the game's own fonts,
  art and colours: a panel, the page's title, a row per item with its value, a cursor
  beside the focused row, a slider's bar, and the prompt the menu waits on.

      Cauldron2D.Menu.Layout.items(menu,
        font: :menu,
        title_font: :title,
        panel: :frame,
        cursor: :pointer,
        slider: {:slider_empty, :slider_full},
        colours: %{text: {200, 190, 170}, focused: {255, 230, 140}, value: {150, 200, 255}}
      )

  ## Options

    * `:font` — the font rows are written in. Required
    * `:title_font` — the font of the page's title. Default `:font`
    * `:panel` — an art drawn behind the menu as nine slices, `{art, border}` or an art
      (border a third of its smaller side). Default none
    * `:cursor` — an art drawn left of the focused row. Default none: the focused row
      is drawn in `:focused` alone
    * `:slider` — `{empty, full}`, two arts of one size: a slider's track and the part of
      it filled to the slider's value. Default none: the value is written as a percent
    * `:colours` — `%{text, focused, value, title, dim, prompt}`, each `{r, g, b}`; any
      left out are the font's own colours
    * `:at` — `{x, y}` and `:anchor` — where the menu's box goes on the pane, as a
      `Cauldron2D.Screen` item takes them. Default the pane's centre
    * `:width` — the box's width in pixels. Default 160
    * `:rows` — how many rows fit; more scroll with the cursor. Default 8
    * `:row` — pixels from one row to the next. Default the font's line
    * `:padding` — pixels between the box's edge and what is in it. Default 8
    * `:outline`, `:shadow` — `{r, g, b}` drawn around or behind every text
  """

  alias Cauldron.Menu
  alias Cauldron2D.{Atlas, Screen}
  alias Cauldron2D.Font

  @doc "The menu's items to draw, against `atlas`; see the module documentation."
  @spec items(Menu.t(), Atlas.name() | Atlas.t(), keyword()) :: [Screen.item()]
  def items(%Menu{} = menu, atlas, opts) do
    atlas = Atlas.fetch(atlas)
    layout = layout(atlas, opts)
    {first, rows} = Menu.window(menu, layout.rows)

    box = box(layout, length(rows), Menu.prompt(menu) != nil)

    panel(layout, box) ++
      title(layout, box, Menu.title(menu)) ++
      Enum.flat_map(rows, &row(layout, box, &1, &1.index - first)) ++
      prompt(layout, box, Menu.prompt(menu))
  end

  defp layout(atlas, opts) do
    font_name = Keyword.fetch!(opts, :font)
    font = Atlas.font!(atlas, font_name)
    title_name = Keyword.get(opts, :title_font, font_name)

    %{
      atlas: atlas,
      font: font_name,
      line: font.line,
      title_font: title_name,
      title_line: Atlas.font!(atlas, title_name).line,
      panel: Keyword.get(opts, :panel),
      cursor: Keyword.get(opts, :cursor),
      slider: Keyword.get(opts, :slider),
      colours: Keyword.get(opts, :colours, %{}),
      at: Keyword.get(opts, :at, {0, 0}),
      anchor: Keyword.get(opts, :anchor, :centre),
      width: Keyword.get(opts, :width, 160),
      rows: Keyword.get(opts, :rows, 8),
      row: Keyword.get(opts, :row, font.line),
      padding: Keyword.get(opts, :padding, 8),
      effects: Keyword.take(opts, [:outline, :shadow])
    }
  end

  defp box(layout, count, prompt?) do
    height =
      2 * layout.padding + layout.title_line + layout.row * (count + if(prompt?, do: 2, else: 0))

    %{width: layout.width, height: height}
  end

  defp panel(%{panel: nil}, _box), do: []

  defp panel(layout, box) do
    {art, opts} =
      case layout.panel do
        {art, border} -> {art, [border: border]}
        art -> {art, []}
      end

    [{:panel, art, corner(layout, box), {box.width, box.height}, placing(layout) ++ opts}]
  end

  defp title(layout, box, text) do
    {left, top} = corner(layout, box)
    x = left + div(box.width - text_width(layout, layout.title_font, text), 2)
    [{:text, layout.title_font, text, {x, top + layout.padding}, text_opts(layout, :title)}]
  end

  defp row(layout, box, row, slot) do
    {left, top} = corner(layout, box)
    y = top + layout.padding + layout.title_line + slot * layout.row
    x = left + layout.padding + cursor_room(layout)
    colour = if row.focused?, do: :focused, else: :text

    cursor(layout, row, {left + layout.padding, y}) ++
      [{:text, layout.font, row.label, {x, y}, text_opts(layout, colour)}] ++
      value(layout, row, {left + box.width - layout.padding, y})
  end

  defp cursor(%{cursor: nil}, _row, _at), do: []
  defp cursor(_layout, %{focused?: false}, _at), do: []
  defp cursor(layout, _row, at), do: [{:art, layout.cursor, at, placing(layout)}]

  defp cursor_room(%{cursor: nil}), do: 0

  defp cursor_room(layout) do
    {width, _height} = Atlas.entry(layout.atlas, layout.cursor).size
    width + 4
  end

  defp value(%{slider: {empty, full}} = layout, %{kind: :slider, fraction: fraction}, {right, y}) do
    {width, _height} = Atlas.entry(layout.atlas, empty).size
    at = {right - width, y}
    [{:art, empty, at, placing(layout)}, {:bar, full, at, fraction, placing(layout)}]
  end

  defp value(_layout, %{value: nil}, _at), do: []

  defp value(layout, %{value: text, waiting?: waiting?}, {right, y}) do
    shown = if waiting?, do: text <> "_", else: text
    width = text_width(layout, layout.font, shown)
    [{:text, layout.font, shown, {right - width, y}, text_opts(layout, :value)}]
  end

  defp prompt(_layout, _box, nil), do: []

  defp prompt(layout, box, prompt) do
    {left, top} = corner(layout, box)
    y = top + box.height - layout.padding - layout.row
    text = prompt_text(prompt)
    x = left + div(box.width - text_width(layout, layout.font, text), 2)
    [{:text, layout.font, text, {x, y}, text_opts(layout, :prompt)}]
  end

  defp prompt_text(%{kind: :confirm, pad?: true, text: text}), do: text <> "  A YES  B NO"
  defp prompt_text(%{kind: :confirm, text: text}), do: text <> "  Y / N"
  defp prompt_text(%{kind: :binding, text: text}), do: "PRESS A KEY FOR " <> text
  defp prompt_text(%{kind: :typing, text: text}), do: "TYPE " <> text <> ", ENTER TO KEEP"

  defp text_width(layout, font, text), do: Font.width(Atlas.font!(layout.atlas, font), text)

  defp corner(%{at: {x, y}} = layout, box) do
    {across, down} = Screen.fractions(layout.anchor)
    {x - round(box.width * across), y - round(box.height * down)}
  end

  defp placing(layout), do: [anchor: layout.anchor, pivot: :top_left]

  defp text_opts(layout, colour_key) do
    case Map.get(layout.colours, colour_key) do
      nil -> placing(layout) ++ layout.effects
      colour -> [colour: colour] ++ placing(layout) ++ layout.effects
    end
  end
end
