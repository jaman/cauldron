defmodule Greenware.Render do
  @moduledoc """
  The painter. One 640 by 360 picture for every screen: the hub, a scene, a mending,
  a conversation, a choice, an ending, the title, and the pause menu over any of them.
  """

  alias Cauldron2D.Raster
  alias Greenware.{Art, Canvas, Fonts, Layout, Mend, Palette, UI}

  @w 640
  @h 360

  @doc "The frame for a view and the client's look."
  def frame(view, look) do
    canvas = Canvas.new(@w, @h, Palette.c(:soot))

    canvas =
      case view.screen do
        :mend -> mend_screen(canvas, view)
        :hub -> hub_screen(canvas, view)
        :scene -> scene_screen(canvas, view)
        :ending -> ending_screen(canvas, view)
        _ -> hub_screen(canvas, view)
      end

    canvas =
      if view.choice do
        choice_overlay(canvas, view.choice)
      else
        canvas
      end

    canvas =
      if view.dialogue do
        dialogue_overlay(canvas, view.dialogue)
      else
        canvas
      end

    canvas =
      if view.mode == :ending or view.screen == :ending do
        ending_overlay(canvas, view)
      else
        canvas
      end

    canvas =
      case Map.get(look, :menu) do
        nil -> canvas
        menu -> pause_overlay(canvas, menu)
      end

    canvas =
      if view.message && view.dialogue == nil do
        message_tag(canvas, view.message)
      else
        canvas
      end

    fade(canvas, view) |> Canvas.finish()
  end

  defp message_tag(canvas, text) do
    width = min(620, Fonts.body_width(text) + 24)
    x = div(@w - width, 2)

    canvas
    |> UI.panel({x, 292, width, 24}, colour: {54, 37, 25, 242}, border: Palette.a(:gold, 0.5))
    |> Canvas.text(Fonts.body(), text, {x + 12, 294}, colour: Palette.c(:gold), wrap: width - 24)
  end

  # -- hub -----------------------------------------------------------------

  defp hub_screen(canvas, view) do
    hub =
      view.hub || %{title: "THE BAKE", subtitle: "", act: view.act, bg: :workshop, entries: []}

    canvas
    |> Canvas.background(Art.background(hub.bg))
    |> glow({520, 96}, 110, 0.22)
    |> dust(view.time, 28)
    |> top_bar(view, hub.title, hub.subtitle)
    |> hub_entries(hub, view)
    |> hub_figures(hub, view)
  end

  defp hub_entries(canvas, hub, view) do
    entries = hub.entries

    Enum.reduce(Enum.with_index(entries), canvas, fn {entry, index}, c ->
      {x, y, width, height} = entry.rect
      selected? = index == view.selected
      available? = entry.available?
      done? = entry.done?

      c =
        c
        |> UI.panel({x, y, width, height},
          colour: if(selected?, do: {73, 50, 35, 250}, else: {43, 31, 25, 245}),
          border: if(selected?, do: Palette.c(:amber), else: {22, 16, 13, 255})
        )

      c =
        if selected? do
          UI.focus_ring(c, {x, y, width, height}, Palette.a(:gold, 0.8))
        else
          c
        end

      icon = if done?, do: Art.icon_mended(entry.icon), else: Art.icon_binary(entry.icon)
      icon_size = design_dims(icon)

      c =
        c
        |> Canvas.sprite(icon, {x + div(width, 2) - div(elem(icon_size, 0), 2), y + 18},
          alpha: if(available?, do: 1.0, else: 0.25)
        )

      label_colour = if available?, do: UI.paper(), else: Palette.a(:parchment, 0.4)

      c =
        c
        |> Canvas.text(Fonts.body(), entry.label, {x + 8, y + 68},
          colour: label_colour,
          wrap: width - 16,
          align: :centre
        )
        |> Canvas.text(
          Fonts.body(),
          cond do
            done? -> "MENDED"
            not available? -> "NOT YET"
            entry.optional? -> "OPTIONAL"
            true -> "READY"
          end,
          {x + 8, y + 98},
          colour: if(done?, do: Palette.c(:gold), else: Palette.a(:sage, 0.85)),
          align: :centre,
          wrap: width - 16
        )

      c =
        if done? do
          c
          |> Canvas.circle({x + width - 18, y + 18}, 10, Palette.a(:gold, 0.2))
          |> Canvas.text(Fonts.body(), "M", {x + width - 22, y + 9}, colour: Palette.c(:gold))
        else
          c
        end

      if not available? do
        Canvas.rect(c, {x, y}, {width, height}, {10, 8, 7, 120})
      else
        c
      end
    end)
  end

  defp hub_figures(canvas, _hub, view) do
    bob = if view.options[:reduced_motion], do: 0, else: round(2 * :math.sin(view.time * 1.4))

    canvas
    |> Canvas.art(
      Art.figure_binary(:greenware),
      {8 + elem(boil(view, 1), 0), 178 + bob + elem(boil(view, 1), 1)}
    )
    |> Canvas.art(
      Art.figure_binary(:cat),
      {584 + elem(boil(view, 2), 0), 238 + bob + elem(boil(view, 2), 1)}
    )
  end

  # -- scene ---------------------------------------------------------------

  defp scene_screen(canvas, view) do
    scene = view.scene || %{bg: :workshop, title: "", subtitle: "", figures: [], hotspot: nil}

    canvas
    |> Canvas.background(Art.background(scene.bg))
    |> glow({512, 92}, 110, 0.2)
    |> dust(view.time, 34)
    |> scene_objects(scene, view)
    |> top_bar(view, scene.title, scene.subtitle)
    |> objective(scene, view)
  end

  defp scene_objects(canvas, scene, view) do
    c =
      Enum.reduce(scene.figures, canvas, fn {kind, x, y}, c ->
        figure = Art.figure_binary(kind)
        {width, height} = design_dims(figure)

        bob =
          if view.options[:reduced_motion], do: 0, else: round(1 * :math.sin(view.time * 1.8 + x))

        Canvas.art(c, figure, {x - div(width, 2), y - height - 20 + bob})
      end)

    c =
      case scene.prop do
        nil ->
          c

        {kind, x, y} ->
          prop =
            if view.scene.stage in [:fixed, :used],
              do: Art.prop_mended_binary(kind),
              else: Art.prop_binary(kind)

          {width, height} = design_dims(prop)
          {bx, by} = boil(view, y)
          Canvas.art(c, prop, {x - div(width, 2) + bx, y - height - 10 + by})
      end

    c
    |> use_effect(scene, view)
    |> hotspot(scene.hotspot, view)
  end

  defp use_effect(canvas, _scene, %{scene: %{stage: :broken}}), do: canvas
  defp use_effect(canvas, _scene, %{scene: nil}), do: canvas

  defp use_effect(canvas, scene, view) do
    case scene.prop do
      nil ->
        canvas

      {kind, x, y} ->
        prop = Art.prop_binary(kind)
        {width, height} = design_dims(prop)
        stage = view.scene.stage

        canvas =
          if stage in [:fixed, :used] do
            canvas = glow(canvas, {x, y - div(height, 2)}, 62, 0.28)

            canvas =
              if Art.mended?(kind) do
                canvas
              else
                canvas
                |> Canvas.line(
                  {x - div(width, 4), y - height + div(height, 3)},
                  {x + div(width, 5), y - div(height, 3)},
                  Palette.a(:gold, 0.9),
                  thickness: 2
                )
                |> Canvas.line(
                  {x + div(width, 5), y - div(height, 3)},
                  {x + div(width, 3), y - height + div(height, 4)},
                  Palette.a(:gold, 0.7),
                  thickness: 2
                )
              end

            if kind == :bucket do
              canvas
              |> Canvas.circle({x, y - 27}, 14, Palette.c(:terracotta))
              |> Canvas.circle({x, y - 27}, 5, Palette.a(:gold, 0.8))
            else
              canvas
            end
          else
            canvas
          end

        if stage == :used do
          use_fx(canvas, view.scene.use.effect, x, y, width, height)
        else
          canvas
        end
    end
  end

  defp use_fx(canvas, :water, x, y, width, height) do
    Enum.reduce(1..5, canvas, fn i, c ->
      Canvas.circle(
        c,
        {x - div(width, 3) + i * 9, y - div(height, 3) + i * 4},
        2 + i,
        Palette.a(:teal, 0.35)
      )
    end)
  end

  defp use_fx(canvas, :bird, x, y, _width, height) do
    bird = Art.prop_binary(:bird)
    {w, _h} = design_dims(bird)
    scale = 0.45
    Canvas.art(canvas, bird, {x + div(w, 2), y - height - 20}, scale: {scale, scale}, alpha: 0.9)
  end

  defp use_fx(canvas, :light, x, y, width, height) do
    glow(canvas, {x, y - div(height, 2)}, 88, 0.55)
    |> Canvas.circle({x - div(width, 4), y - height}, 3, Palette.a(:amber, 0.8))
  end

  defp use_fx(canvas, :dawn, _x, _y, _width, _height) do
    Canvas.rect(canvas, {0, 0}, {@w, @h}, {255, 206, 120, 35})
  end

  defp use_fx(canvas, :beat, x, y, _width, height) do
    Enum.reduce(1..3, canvas, fn i, c ->
      Canvas.circle(c, {x, y - div(height, 2)}, 12 * i, Palette.a(:rose, 0.16))
    end)
  end

  defp use_fx(canvas, effect, x, y, _width, height) do
    colour =
      case effect do
        :open -> Palette.c(:gold)
        :arm -> Palette.c(:sage)
        :ring -> Palette.c(:bone)
        :stand -> Palette.c(:rose)
        :spin -> Palette.c(:amber)
        :reflect -> Palette.c(:teal)
        :music -> Palette.c(:gold)
        :cross -> Palette.c(:gold)
        _ -> Palette.c(:gold)
      end

    Enum.reduce(1..4, canvas, fn i, c ->
      Canvas.circle(c, {x + i * 7, y - height - i * 7}, 2 + rem(i, 2), Palette.a(colour, 0.5))
    end)
  end

  defp hotspot(canvas, nil, _view), do: canvas

  defp hotspot(canvas, %{rect: rect, label: label, kind: kind}, view) do
    {x, y, width, height} = rect
    hovered? = Layout.in_rect?(Layout.cursor(view), rect)
    completed? = view.scene && view.scene.completed?

    canvas =
      cond do
        completed? ->
          canvas
          |> Canvas.circle({x + width - 12, y + 12}, 10, Palette.a(:gold, 0.2))
          |> Canvas.text(Fonts.body(), "M", {x + width - 16, y + 3}, colour: Palette.c(:gold))

        hovered? or view.guided ->
          canvas
          |> UI.dashed(
            rect,
            if(hovered?, do: Palette.c(:gold), else: Palette.a(:amber, 0.45)),
            0.9
          )
          |> then(fn c ->
            if hovered? do
              label_tag(c, label, {12, 102})
            else
              c
            end
          end)

        true ->
          canvas
          |> UI.dashed(rect, Palette.a(:amber, 0.22), 0.9)
      end

    cond do
      hovered? and kind == :use and not completed? ->
        Canvas.text(canvas, Fonts.body(), "USE", {x + width - 4, y + height + 2},
          colour: Palette.c(:gold)
        )

      hovered? and kind == :mend and not completed? ->
        Canvas.text(canvas, Fonts.body(), "MEND", {x + width - 4, y + height + 2},
          colour: Palette.c(:gold)
        )

      true ->
        canvas
    end
  end

  defp label_tag(canvas, label, {x, y}) do
    width = Fonts.body_width(label) + 12

    canvas
    |> UI.panel({x, y, width, 18}, colour: {38, 27, 21, 230}, border: {20, 14, 11, 255})
    |> Canvas.text(Fonts.body(), label, {x + 6, y + 0}, colour: Palette.c(:gold))
  end

  # -- mending -------------------------------------------------------------

  defp mend_screen(canvas, view) do
    mend = view.mend
    puzzle = mend.puzzle

    canvas
    |> Canvas.background(Art.background((view.scene && view.scene.bg) || :workshop))
    |> Canvas.rect({0, 0}, {@w, @h}, {8, 6, 5, 176})
    |> UI.panel({8, 8, 624, 344}, colour: {39, 28, 22, 248})
    |> Canvas.text(Fonts.body(), String.upcase(puzzle.title), {24, 16},
      colour: Palette.c(:gold),
      shadow: Palette.a(:soot, 0.8)
    )
    |> Canvas.text(Fonts.body(), puzzle.goal, {24, 42}, colour: Palette.c(:parchment), wrap: 590)
    |> mend_thumbnail(puzzle)
    |> mend_field(mend, view)
    |> mend_tools(mend, view)
    |> mend_hud(mend, view)
    |> mend_result(mend)
  end

  defp mend_thumbnail(canvas, puzzle) do
    prop = Art.prop_binary(puzzle.id)
    {w, h} = design_dims(prop)
    scale = min(80 / w, 80 / h)

    canvas
    |> UI.panel({14, 96, 88, 88}, colour: {31, 22, 17, 220})
    |> Canvas.art(prop, {18, 100}, scale: {scale, scale})
  end

  defp mend_field(canvas, mend, view) do
    guided? = view.options[:guided] || view.guided
    raster = field_raster(mend, guided?)
    {x, y, width, height} = Layout.field_rect()

    canvas
    |> Canvas.rect({x - 4, y - 4}, {width + 8, height + 8}, {20, 14, 11, 255})
    |> Canvas.art(raster, {x, y}, scale: {3, 3})
    |> Canvas.box({x - 1, y - 1}, {width + 2, height + 2}, {71, 49, 34, 255})
    |> then(fn c ->
      if view.mend.done? do
        Canvas.rect(c, {x, y}, {width, height}, {8, 6, 4, 120})
      else
        c
      end
    end)
  end

  defp mend_tools(canvas, _mend, view) do
    c =
      Enum.reduce(Enum.with_index(Mend.tool_rows()), canvas, fn {{tool, label, key, _desc}, index},
                                                                c ->
        rect = Layout.tool_rect(index)
        selected? = view.tool == tool
        {x, y, width, _height} = rect

        c
        |> Canvas.rect(
          rect_point(rect),
          rect_size(rect),
          if(selected?, do: {88, 57, 37, 255}, else: {47, 34, 27, 255})
        )
        |> Canvas.box(
          rect_point(rect),
          rect_size(rect),
          if(selected?, do: Palette.c(:amber), else: {26, 19, 15, 255})
        )
        |> Canvas.text(Fonts.body(), label, {x + 8, y + 2},
          colour: if(selected?, do: Palette.c(:gold), else: Palette.c(:bone))
        )
        |> Canvas.text(Fonts.body(), key, {x + width - 18, y + 2}, colour: Palette.a(:sage, 0.9))
      end)

    c
  end

  defp mend_hud(canvas, mend, view) do
    {fx, fy, _fw, _fh} = Layout.field_rect()
    wet = round(mend.wet)

    canvas
    |> Canvas.text(
      Fonts.body(),
      "CLAY #{round(mend.clay)}   WATER #{round(mend.water)}",
      {fx, fy + 220},
      colour: Palette.a(:sage, 0.95)
    )
    |> Canvas.text(Fonts.body(), "FIRE #{round(mend.fired)}   WET #{wet}", {fx, fy + 240},
      colour: Palette.a(:sage, 0.85)
    )
    |> UI.button(Layout.test_button(), "TEST", focused?: false)
    |> UI.button(Layout.reset_button(), "RESET", focused?: false)
    |> UI.button(Layout.back_button(), "BACK", focused?: false)
    |> cursor(Layout.cursor(view))
  end

  defp cursor(canvas, {x, y}) do
    canvas
    |> Canvas.circle({x, y}, 7, Palette.a(:gold, 0.2))
    |> Canvas.circle({x, y}, 3, Palette.c(:gold))
    |> Canvas.circle({x, y}, 1, Palette.c(:ink))
  end

  defp mend_result(canvas, %{result: nil}), do: canvas

  defp mend_result(canvas, %{result: %{rows: rows, ok?: ok?}}) do
    {_x, _y, _width, _height} = Layout.field_rect()
    panel_width = 360
    panel_height = 58 + length(rows) * 22
    left = 40
    top = 122

    c =
      canvas
      |> UI.panel({left, top, panel_width, panel_height}, colour: {33, 24, 19, 248})
      |> Canvas.text(Fonts.body(), if(ok?, do: "IT HOLDS", else: "NOT YET"), {left + 14, top + 8},
        colour: if(ok?, do: Palette.c(:gold), else: Palette.c(:rose))
      )
      |> Canvas.text(
        Fonts.body(),
        if(ok?, do: "ENTER TO KEEP THE MEND", else: "T TO TEST AGAIN"),
        {left + 14, top + panel_height - 20},
        colour: Palette.a(:parchment, 0.7)
      )

    Enum.reduce(Enum.with_index(rows), c, fn {row, index}, c ->
      Canvas.text(
        c,
        Fonts.body(),
        "#{if(row.ok?, do: "+", else: "-")} #{row.label}",
        {left + 14, top + 32 + index * 22},
        colour: if(row.ok?, do: Palette.c(:sage), else: Palette.a(:rose, 0.9))
      )
      |> Canvas.text(Fonts.body(), row.detail, {left + panel_width - 88, top + 32 + index * 22},
        colour: Palette.a(:parchment, 0.8)
      )
    end)
  end

  # -- dialogue and choices ------------------------------------------------

  defp dialogue_overlay(canvas, dialogue) do
    {x, y, width, height} = Layout.dialogue_rect()
    speaker = UI.speaker(dialogue.speaker)
    text = dialogue.text

    canvas
    |> Canvas.rect({x - 4, y - 4}, {width + 8, height + 8}, {8, 6, 5, 110})
    |> UI.dialogue({x, y, width, height}, speaker, text)
  end

  defp choice_overlay(canvas, choice) do
    title = choice.title
    options = choice.options
    selected = choice.selected

    c =
      canvas
      |> Canvas.rect({0, 0}, {@w, @h}, {8, 6, 5, 160})
      |> Canvas.text(Fonts.display(), title, {40, 92},
        colour: Palette.c(:gold),
        shadow: Palette.a(:soot, 0.8)
      )
      |> Canvas.text(Fonts.body(), "Three ways to finish the story.", {40, 142},
        colour: Palette.c(:parchment)
      )

    Enum.reduce(Enum.with_index(options), c, fn {option, index}, c ->
      {x, y, width, height} = Layout.choice_rect(index)
      focused? = index == selected

      c
      |> UI.panel({x, y, width, height},
        colour: if(focused?, do: {78, 52, 35, 250}, else: {42, 31, 25, 245}),
        border: if(focused?, do: Palette.c(:amber), else: {22, 16, 13, 255})
      )
      |> Canvas.text(Fonts.body(), option.label, {x + 10, y + 10},
        colour: if(focused?, do: Palette.c(:gold), else: Palette.c(:bone)),
        wrap: width - 20
      )
      |> Canvas.text(Fonts.body(), option.description, {x + 10, y + 42},
        colour: Palette.a(:parchment, 0.8),
        wrap: width - 20
      )
      |> then(fn c ->
        if focused?, do: UI.focus_ring(c, {x, y, width, height}, Palette.a(:gold, 0.7)), else: c
      end)
    end)
    |> Canvas.text(Fonts.body(), "LEFT / RIGHT CHOOSE    ENTER DECIDES", {40, 330},
      colour: Palette.a(:parchment, 0.75)
    )
  end

  defp ending_screen(canvas, view) do
    kind = (view.ending && view.ending.kind) || :green
    bg = if kind == :fire, do: :kiln, else: :workshop

    canvas
    |> Canvas.background(Art.background(bg))
    |> Canvas.rect({0, 0}, {@w, @h}, {8, 6, 5, 120})
    |> Canvas.text(Fonts.display(), (view.ending && view.ending.title) || "GREENWARE", {44, 42},
      colour: Palette.c(:gold),
      shadow: Palette.a(:soot, 0.8)
    )
  end

  defp ending_overlay(canvas, view) do
    ending = view.ending || %{pages: [], title: "", text: "", speaker: nil}

    canvas
    |> Canvas.rect({0, 0}, {@w, @h}, {8, 6, 5, 120})
    |> Canvas.text(Fonts.body(), ending.text, {44, 150},
      colour: Palette.c(:paper),
      wrap: 552
    )
    |> then(fn c ->
      if ending.speaker && ending.speaker != :narrator do
        Canvas.text(c, Fonts.body(), String.upcase(UI.speaker(ending.speaker) || ""), {44, 138},
          colour: Palette.c(:amber)
        )
      else
        c
      end
    end)
    |> Canvas.text(Fonts.body(), "ENTER", {44, 320}, colour: Palette.a(:parchment, 0.7))
  end

  # -- title and summary ---------------------------------------------------

  def title(state, _settings) do
    canvas =
      Canvas.new(@w, @h, Art.background(:workshop))
      |> glow({486, 84}, 130, 0.3)
      |> dust(state.clock, 54)
      |> Canvas.rect({0, 0}, {@w, @h}, {6, 5, 4, 72})
      |> Canvas.text(Fonts.display(), "GREENWARE", {46, 44},
        colour: Palette.c(:gold),
        shadow: Palette.a(:soot, 0.9)
      )
      |> Canvas.text(Fonts.body(), "A STOP-MOTION STORY ABOUT MENDING", {50, 104},
        colour: Palette.c(:parchment)
      )
      |> Canvas.text(
        Fonts.body(),
        "a small clay figure, a cold kiln, and a world that is drying out",
        {50, 146},
        colour: Palette.a(:sage, 0.9),
        wrap: 300
      )
      |> Canvas.art(Art.figure_binary(:greenware), {60, 214}, alpha: 0.96)
      |> Canvas.art(Art.figure_binary(:cat), {306, 290}, alpha: 0.96)
      |> UI.menu(state.menu, Layout.title_menu(), 236, rows: 7)
      |> footer("ARROWS CHOOSE    ENTER PICKS    ESC BACK")

    Canvas.finish(canvas)
  end

  def summary(context) do
    outcome = context.outcome || %{title: "THE END", lines: []}
    ending = context.ending || %{title: outcome.title}

    canvas =
      Canvas.new(@w, @h, Art.background(:workshop))
      |> Canvas.rect({0, 0}, {@w, @h}, {6, 5, 4, 110})
      |> Canvas.text(Fonts.display(), ending.title, {44, 40},
        colour: Palette.c(:gold),
        shadow: Palette.a(:soot, 0.8)
      )
      |> Canvas.text(Fonts.body(), "THE BAKE IS QUIET.", {46, 100}, colour: Palette.c(:parchment))

    canvas =
      Enum.reduce(Enum.with_index(outcome.lines), canvas, fn {line, index}, c ->
        Canvas.text(c, Fonts.body(), line, {46, 132 + index * 24},
          colour: Palette.c(:paper),
          wrap: 548
        )
      end)

    canvas
    |> Canvas.art(Art.figure_binary(:greenware), {18, 188}, alpha: 0.9, scale: {0.55, 0.55})
    |> Canvas.text(Fonts.body(), "THANK YOU FOR MENDING.", {46, 306}, colour: Palette.c(:amber))
    |> Canvas.text(Fonts.body(), "ENTER RETURNS TO THE TITLE", {46, 330},
      colour: Palette.a(:parchment, 0.65)
    )
    |> then(fn c ->
      case Map.get(context, :menu) do
        nil -> c
        menu -> UI.menu(c, menu, {380, 250}, 230, rows: 2)
      end
    end)
    |> Canvas.finish()
  end

  # -- shared bits ---------------------------------------------------------

  defp top_bar(canvas, view, title, subtitle) do
    canvas
    |> Canvas.rect({0, 0}, {@w, 46}, {10, 8, 6, 150})
    |> Canvas.text(Fonts.body(), "ACT #{view.act}", {18, 8}, colour: Palette.c(:amber))
    |> Canvas.text(Fonts.body(), String.upcase(title), {96, 4},
      colour: Palette.c(:gold),
      shadow: Palette.a(:soot, 0.7)
    )
    |> Canvas.text(Fonts.body(), subtitle, {98, 26}, colour: Palette.a(:parchment, 0.8))
  end

  defp objective(canvas, scene, view) do
    {label, colour, text} =
      case view.scene.stage do
        :fixed -> {"USE", Palette.c(:gold), view.scene.use.label}
        :used -> {"DONE", Palette.c(:sage), "The thing is mended and used."}
        _ -> {"MEND", Palette.c(:gold), scene.objective}
      end

    canvas
    |> Canvas.rect({0, 46}, {@w, 50}, {9, 7, 5, 150})
    |> Canvas.text(Fonts.body(), label, {10, 51}, colour: colour)
    |> Canvas.text(Fonts.body(), text, {98, 51}, colour: Palette.c(:parchment), wrap: 534)
  end

  defp footer(canvas, text) do
    Canvas.text(canvas, Fonts.body(), text, {18, 338}, colour: Palette.a(:parchment, 0.6))
  end

  defp pause_overlay(canvas, menu) do
    canvas
    |> Canvas.rect({0, 0}, {@w, @h}, {8, 6, 5, 176})
    |> Canvas.text(Fonts.display(), "PAUSED", {44, 28},
      colour: Palette.c(:gold),
      shadow: Palette.a(:soot, 0.8)
    )
    |> UI.menu(menu, {44, 80}, 260, rows: 7)
  end

  defp fade(canvas, view) do
    alpha = Map.get(view, :fade, 0.0)

    if alpha > 0.001 do
      Canvas.rect(canvas, {0, 0}, {@w, @h}, {7, 5, 4, round(alpha * 255)})
    else
      canvas
    end
  end

  defp glow(canvas, {x, y}, radius, alpha) do
    glow = Art.glow_binary(radius)
    {width, height} = design_dims(glow)
    Canvas.art(canvas, glow, {x - div(width, 2), y - div(height, 2)}, alpha: alpha)
  end

  defp dust(canvas, time, count) do
    Enum.reduce(1..count, canvas, fn index, c ->
      x = :erlang.phash2({:dust_x, index}, @w)
      speed = 4 + :erlang.phash2({:dust_speed, index}, 12)
      y = :math.fmod(:erlang.phash2({:dust_y, index}, @h) + time * speed, @h)
      alpha = 0.12 + :erlang.phash2({:dust_a, index}, 80) / 400

      Canvas.circle(
        c,
        {x, round(y)},
        1 + :erlang.phash2({:dust_r, index}, 2),
        Palette.a(:amber, alpha)
      )
    end)
  end

  # -- the clay field ------------------------------------------------------

  defp field_raster(mend, guided?) do
    {cells_w, cells_h} = {Mend.width(), Mend.height()}
    width = cells_w * 2
    height = cells_h * 2
    puzzle = mend.puzzle
    base = Palette.c(puzzle.colour)
    dark = Palette.shade(base, -0.62)
    light = Palette.shade(base, 0.38)
    holes = puzzle.holes
    wet = mend.wet / 100
    fired = mend.fired / 100
    mask = puzzle.mask

    rgba =
      for y <- 0..(height - 1), into: <<>> do
        for x <- 0..(width - 1), into: <<>> do
          cx = div(x, 2)
          cy = div(y, 2)
          value = Mend.at(mend, cx, cy)
          wire? = MapSet.member?(mend.wire, {cx, cy})
          hole? = MapSet.member?(holes, {cx, cy})

          cond do
            wire? ->
              <<196, 151, 78, 255>>

            value > 0 ->
              clay_pixel(mend, cx, cy, value, dark, light, wet, fired, mask)

            hole? and guided? ->
              <<224, 165, 86, 205>>

            hole? ->
              <<48, 22, 17, 245>>

            true ->
              <<0, 0, 0, 0>>
          end
        end
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp clay_pixel(mend, cx, cy, value, dark, light, wet, fired, mask) do
    t = value / 255
    {r, g, b, _} = Palette.mix(dark, light, 0.30 + 0.52 * t)

    dx = Mend.at(mend, cx + 1, cy) - Mend.at(mend, cx - 1, cy)
    dy = Mend.at(mend, cx, cy + 1) - Mend.at(mend, cx, cy - 1)
    {nx, ny, nz} = normal(dx / 150, dy / 150)

    diffuse = max(0.0, nx * -0.38 + ny * -0.55 + nz * 0.74)

    rim =
      if edge?(mend, cx, cy, mask), do: 0.25, else: 0.0

    shade = 0.38 + 0.72 * diffuse + rim

    spec =
      if wet > 0.35 and diffuse > 0.25, do: 38 * wet * :math.pow(diffuse, 6), else: 0.0

    fire = if fired > 0.55, do: (fired - 0.55) * 90, else: 0.0

    rr = clamp(round(r * shade + spec + fire))
    gg = clamp(round(g * shade + spec * 0.72 + fire * 0.4))
    bb = clamp(round(b * shade + spec * 0.45 + fire * 0.15))
    <<rr, gg, bb, 255>>
  end

  defp normal(dx, dy) do
    len = :math.sqrt(dx * dx + dy * dy + 1)
    {-dx / len, -dy / len, 1 / len}
  end

  defp edge?(mend, cx, cy, mask) do
    MapSet.member?(mask, {cx, cy}) and
      Enum.any?([{cx - 1, cy}, {cx + 1, cy}, {cx, cy - 1}, {cx, cy + 1}], fn {x, y} ->
        Mend.at(mend, x, y) == 0
      end)
  end

  defp clamp(value), do: value |> max(0) |> min(255)

  defp boil(view, seed) do
    if view.options[:reduced_motion] do
      {0, 0}
    else
      case rem(floor(view.time * 12) + :erlang.phash2(seed, 5), 5) do
        0 -> {0, 0}
        1 -> {0.5, 0}
        2 -> {-0.5, 0}
        3 -> {0, 0.5}
        _ -> {0, -0.5}
      end
    end
  end

  defp design_dims(%FrenchCurve.Raster{} = raster) do
    {width, height} = Raster.dimensions(raster)
    {div(width, 2), div(height, 2)}
  end

  defp design_dims({_rgba, width, height}), do: {div(width, 2), div(height, 2)}

  defp rect_point({x, y, _w, _h}), do: {x, y}
  defp rect_size({_x, _y, w, h}), do: {w, h}

  @doc "The frame fitted into a front end's real pane, with clay matte rather than black bars."
  def frame_fit(view, look, size) do
    last({:fit, frame_key(view, look), size}, fn -> fit(frame_cached(view, look), size) end)
  end

  def title_fit(state, settings, size) do
    last({:title_fit, state.menu, settings, size}, fn ->
      fit(title_cached(state, settings), size)
    end)
  end

  def summary_fit(context, size) do
    last({:summary_fit, context, size}, fn -> fit(summary_cached(context), size) end)
  end

  defp fit(base, size) do
    {width, height} = capped(size)
    {base_w, base_h} = Raster.dimensions(base)

    if {base_w, base_h} == {width, height} do
      base
    else
      scale = min(width / base_w, height / base_h)
      shown_w = round(base_w * scale)
      shown_h = round(base_h * scale)

      Cauldron2D.Render.render(
        {width, height},
        [
          {:sprite, base,
           %{position: {div(width - shown_w, 2), div(height - shown_h, 2)}, scale: {scale, scale}}}
        ],
        background: {18, 13, 10, 255}
      )
    end
  end

  defp capped({width, height}) when max(width, height) > 1600 do
    scale = 1600 / max(width, height)
    {max(1, round(width * scale)), max(1, round(height * scale))}
  end

  defp capped(size), do: size

  @doc "The world's frame, reused while nothing visible changed."
  def frame_cached(view, look) do
    last({:frame, frame_key(view, look)}, fn -> frame(view, look) end)
  end

  @doc "The title, reused while its menu is unchanged."
  def title_cached(state, settings) do
    last({:title, state.menu, settings}, fn -> title(state, settings) end)
  end

  @doc "The summary, reused while its menu is unchanged."
  def summary_cached(context) do
    last({:summary, context}, fn -> summary(context) end)
  end

  defp frame_key(view, look) do
    {view.mode, view.screen, view.act, view.hub, view.scene, view.dialogue, view.choice,
     view.ending, view.selected, Map.get(view, :completed, []), Map.get(view, :options, %{}),
     view.tool, view.mend, view.cursor, round(view.fade * 10), Map.get(look, :menu),
     Map.get(look, :menu_frame)}
  end

  defp last(key, fun) do
    table =
      case :ets.whereis(:greenware_frames) do
        :undefined ->
          try do
            :ets.new(:greenware_frames, [:named_table, :set, :public, read_concurrency: true])
          rescue
            ArgumentError -> :greenware_frames
          end

        _ ->
          :greenware_frames
      end

    case :ets.lookup(table, :last) do
      [{:last, ^key, raster}] ->
        raster

      _ ->
        raster = fun.()
        :ets.insert(table, {:last, key, raster})
        raster
    end
  end
end
