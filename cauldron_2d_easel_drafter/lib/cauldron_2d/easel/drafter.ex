defmodule Cauldron2D.Easel.Drafter do
  @moduledoc """
  The atlas editor in the terminal: a drafter application that opens an art directory
  (`Cauldron2D.Easel.Project`), lists its arts, and edits one on a zoomed canvas with
  the palette, the tools and the frames beside it.

      Drafter.run(Cauldron2D.Easel.Drafter, props: %{dir: "priv/art", tile: 16, atlas: :my_game})
      mix cauldron.easel priv/art --tile 16 --atlas my_game

  With `:atlas`, every save installs the directory as that atlas, so a game running in
  the same VM that subscribed to it redraws with the new art.

  ## Keys

  `?` shows every key on screen, from any screen.

  Arts: `↑`/`↓` choose, `Enter` open, `n` new (a name is asked for), `D` derive an art
  from the one chosen (`name = from ART; colour K #rrggbb; flip h ...`, the line as
  `Linocut.Derive` reads it; the name alone derives it unchanged), `y` clone it as a
  picture of its own, `q` quit. A derived art opens for looking; it is changed by its
  line, or cloned.
  Editing: the pointer paints with the tool in hand, and every tool, colour and frame
  in the side panel is a button. `b` brush, `l` line, `r` rectangle, `R` filled
  rectangle, `f` fill, `e` eraser, `i` eyedropper (the next press takes the colour
  under it); `1`–`9` and `0` pick a palette colour, `[`/`]` the one before or after.
  `c` opens the colour picker — a chart of hues and greys with the palette under it —
  and adds the colour chosen under the next free key; `C` opens it for the colour in
  hand; `#` asks for a colour typed as `#rrggbb` instead; `k` renames the key in hand,
  `K` removes it. `h`/`v` flip, `t`/`T` turn, arrows shift the frame. `,`/`.` frame
  before or after, `a` adds a frame, `d` duplicates it, `x` drops it, `<`/`>` move it,
  `o` onion skin, `p` plays and stops, `+`/`-` rate, `z` zoom. `u` undoes, `U` redoes.
  `g` sets the glyph and colour the text renderer draws (`glyph #rrggbb` is asked for).
  The side panel shows the picture at actual size, drawn the way a game draws it: through
  the terminal's graphics where it has them, animated at the picture's rate, or as its
  glyph; `m` shows it tiled, for a picture that is to repeat.
  `s` saves, `w` saves and installs, `Esc` returns to the arts, `^Q` quits. In the
  picker: arrows or the pointer choose, `Enter` takes, `Esc` leaves.

  ## Mount props

    * `:dir` — the art directory. Required
    * `:tile` — the tile size. Required
    * `:art` — an art to open at once. Default: the list of arts
    * `:atlas` — the atlas name saves install into. Default: none
  """

  use Drafter.App

  alias Cauldron2D.{Atlas, Easel}
  alias Cauldron2D.Easel.Drafter.{ActualSize, Canvas, Swatches}
  alias Cauldron2D.Easel.Project

  @tools [:brush, :line, :rect, :filled_rect, :fill, :eraser, :eyedropper]
  @picks ~w(1 2 3 4 5 6 7 8 9 0)
  @free_keys String.graphemes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
  @zooms [2, 4, 6, 8]
  @actual_every_ms 100

  @doc "Make the editor's widgets known to drafter; `mount/1` does this, and an application using the canvas alone does it itself."
  @spec register_widgets() :: :ok
  def register_widgets do
    for widget <- [Canvas, Swatches, Cauldron2D.Drafter.Surface] do
      Code.ensure_loaded!(widget)
      Drafter.Widget.Registry.register(widget)
    end

    :ok
  end

  @impl true
  def mount(props) do
    register_widgets()
    project = Project.open(Map.fetch!(props, :dir), tile: Map.fetch!(props, :tile))

    state = %{
      project: project,
      atlas: Map.get(props, :atlas),
      arts: Project.arts(project),
      selected: 0,
      screen: :arts,
      name: nil,
      easel: nil,
      tool: :brush,
      key: nil,
      anchor: nil,
      preview: nil,
      actual: ActualSize.new(),
      tiled: false,
      onion: false,
      playing: false,
      shown: 0,
      zoom: 4,
      prompt: nil,
      prompt_text: "",
      picker: nil,
      help: nil,
      status: "? shows the keys"
    }

    case Map.get(props, :art) do
      nil -> state
      art -> open(state, art)
    end
  end

  @impl true
  def refresh_rate, do: "30fps"

  @impl true
  def on_ready(state) do
    Drafter.set_timeout(@actual_every_ms, :actual)
    state
  end

  @impl true
  def render(%{help: from} = state) when from != nil do
    lines = help_text() |> String.split("\n") |> Enum.map(&label/1)

    vertical(
      [label("Keys", style: %{bold: true}), label("")] ++
        lines ++
        [
          label("", flex: 1),
          label("? or Esc  back", style: %{fg: :bright_black}),
          label(state.status, style: %{fg: :yellow})
        ]
    )
  end

  def render(%{picker: picker} = state) when picker != nil do
    rows = picker_rows(state)
    {r, g, b} = picker.colour

    vertical([
      label(picker.title, style: %{bold: true}),
      label("arrows or the pointer choose   Enter takes   # types a colour   Esc leaves",
        style: %{fg: :bright_black}
      ),
      {:easel_swatches,
       [
         id: :swatches,
         colours: rows,
         cursor: picker.cursor,
         on_pick: :swatch,
         height: length(rows)
       ]},
      label(""),
      label([{"chosen  ", %{}}, {"      ", %{bg: {r, g, b}}}, {"  #{hex({r, g, b})}", %{}}]),
      label("", flex: 1),
      prompt_row(state),
      label(state.status, style: %{fg: :yellow})
    ])
  end

  def render(%{screen: :arts} = state) do
    me = self()

    rows =
      state.arts
      |> Enum.with_index()
      |> Enum.map(fn {art, index} ->
        marker = if index == state.selected, do: "▶ ", else: "  "

        label(
          marker <>
            "#{art.name}  ·  #{art.frames} frame#{if art.frames == 1, do: "", else: "s"}  ·  #{source(art)}",
          style: if(Map.has_key?(art, :derived), do: %{fg: :cyan}, else: %{})
        )
      end)

    vertical(
      [
        label("Easel  ·  #{state.project.dir}  ·  #{state.project.tile}px tiles",
          style: %{bold: true}
        ),
        label("")
      ] ++
        rows ++
        [
          label(""),
          horizontal(
            [
              compact_button("open", on_click: fn -> send(me, {:easel, :open}) end),
              compact_button("new", on_click: fn -> send(me, {:easel, :new}) end),
              compact_button("derive", on_click: fn -> send(me, {:easel, :derive}) end),
              compact_button("clone", on_click: fn -> send(me, {:easel, :clone}) end),
              compact_button("keys ?", on_click: fn -> send(me, {:easel, :help}) end),
              compact_button("quit", on_click: fn -> send(me, {:easel, :quit}) end)
            ],
            gap: 1
          ),
          label("", flex: 1),
          prompt_row(state),
          label("↑↓ choose   Enter open   n new   D derive   y clone   ? keys   q quit",
            style: %{fg: :bright_black}
          ),
          label(state.status, style: %{fg: :yellow})
        ]
    )
  end

  def render(%{screen: :edit} = state) do
    easel = shown_easel(state)
    {width, height} = Easel.size(easel)

    canvas =
      {:easel_canvas,
       [
         id: :canvas,
         easel: easel,
         zoom: state.zoom,
         onion: state.onion and not state.playing,
         on_paint: :paint,
         flex: 1
       ]}

    vertical([
      label(
        "#{state.name}  ·  #{width}×#{height}  ·  frame #{easel.frame + 1}/#{length(easel.frames)}  ·  #{easel.fps} fps#{if state.playing, do: "  ·  playing", else: ""}",
        style: %{bold: true}
      ),
      horizontal([canvas, vertical(side(state), width: 34, gap: 0)], gap: 1, flex: 1),
      prompt_row(state),
      label(hints(state), style: %{fg: :bright_black}),
      label(state.status, style: %{fg: :yellow})
    ])
  end

  defp compact_button(text, opts), do: button(text, Keyword.put(opts, :compact, true))

  defp shown_easel(%{playing: true, easel: easel, shown: shown}), do: %{easel | frame: shown}
  defp shown_easel(%{easel: easel}), do: easel

  defp side(state) do
    easel = state.easel
    me = self()
    click = fn message -> fn -> send(me, {:easel, message}) end end

    tools =
      Enum.map(
        @tools,
        &compact_button(tool_name(&1),
          id: :"tool_#{&1}",
          on_click: click.({:tool, &1}),
          variant: if(&1 == state.tool, do: :primary, else: :default)
        )
      )

    palette =
      easel.palette
      |> Enum.with_index()
      |> Enum.map(fn {{key, {r, g, b, _a}}, index} ->
        marker = if key == state.key, do: "▶", else: " "

        horizontal(
          [
            label([
              {"#{marker} #{Enum.at(@picks, index, " ")} ", %{}},
              {"  ", %{bg: {r, g, b}}},
              {" #{key} #{hex({r, g, b})}", %{}}
            ]),
            compact_button("use", on_click: click.({:pick, key}))
          ],
          gap: 1
        )
      end)

    frames =
      easel.frames
      |> Enum.with_index()
      |> Enum.map(fn {_frame, index} ->
        compact_button("#{index + 1}",
          on_click: click.({:frame, index}),
          variant: if(index == easel.frame, do: :primary, else: :default)
        )
      end)

    [
      horizontal(
        [
          label("actual size", style: %{fg: :cyan}),
          compact_button("tiled",
            on_click: click.(:tiled),
            variant: if(state.tiled, do: :primary, else: :default)
          )
        ],
        gap: 1
      ),
      {:cauldron_surface,
       [
         id: :actual,
         atlas: state.actual.name,
         focus: {0, 0},
         cell: ActualSize.cell(state.tiled),
         height: actual_rows(easel)
       ]},
      label("tools", style: %{fg: :cyan}),
      horizontal(Enum.take(tools, 4), gap: 1),
      horizontal(Enum.drop(tools, 4), gap: 1),
      label("")
    ] ++
      [label("colours   c picks a new one", style: %{fg: :cyan})] ++
      if(palette == [],
        do: [label("none yet: c adds one", style: %{fg: :bright_black})],
        else: palette
      ) ++
      [
        label(""),
        label("frames   a add  d copy  x drop", style: %{fg: :cyan}),
        horizontal(frames, gap: 1),
        horizontal(
          [
            compact_button("onion",
              on_click: click.(:onion),
              variant: if(state.onion, do: :primary, else: :default)
            ),
            compact_button("play",
              on_click: click.(:play),
              variant: if(state.playing, do: :primary, else: :default)
            ),
            compact_button("zoom #{state.zoom}", on_click: click.(:zoom))
          ],
          gap: 1
        ),
        label(""),
        label("glyph  #{glyph_text(state)}", style: %{fg: :cyan}),
        horizontal(
          [
            compact_button("undo", on_click: click.(:undo)),
            compact_button("redo", on_click: click.(:redo)),
            compact_button("save", on_click: click.(:save)),
            compact_button("install", on_click: click.(:install))
          ],
          gap: 1
        ),
        horizontal(
          [
            compact_button("keys ?", on_click: click.(:help)),
            compact_button("arts", on_click: click.(:arts))
          ],
          gap: 1
        )
      ]
  end

  defp actual_rows(easel), do: max(3, div(max(easel.width, easel.height) * 3 + 15, 16))

  defp tool_name(:filled_rect), do: "box"
  defp tool_name(:eyedropper), do: "pick"
  defp tool_name(tool), do: Atom.to_string(tool)

  defp glyph_text(state) do
    case Project.entry(state.project, state.name) do
      %{glyph: glyph} = entry ->
        "#{inspect(glyph)}#{if entry[:color], do: " " <> hex(entry.color), else: ""}"

      _none ->
        "not set (g)"
    end
  end

  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)

  defp hints(%{tool: tool}),
    do:
      "#{tool_hint(tool)}   ·   c colour   u undo   , . frames   s save   w install   ? keys   Esc arts"

  defp tool_hint(:brush), do: "brush: press or drag to paint"
  defp tool_hint(:line), do: "line: press where it starts, drag to where it ends"
  defp tool_hint(:rect), do: "rectangle: press one corner, drag to the other"
  defp tool_hint(:filled_rect), do: "filled rectangle: press one corner, drag to the other"
  defp tool_hint(:fill), do: "fill: press inside an area to flood it"
  defp tool_hint(:eraser), do: "eraser: press or drag to clear"
  defp tool_hint(:eyedropper), do: "eyedropper: press a pixel to take its colour"

  defp help_text do
    """
    Arts        ↑ ↓ choose    Enter open    n new    D derive (name = from ART; colour K #rrggbb; flip h ...)    y clone    q quit
    Tools       b brush   l line   r rectangle   R filled rectangle   f fill   e eraser   i eyedropper
    Colours     1-9 0 pick   [ ] before/after   c pick a new colour   C change the one in hand
                # type #rrggbb   k rename key   K remove key
    Frame       h v flip   t T turn   arrows shift
    Frames      , . before/after   a add   d duplicate   x drop   < > move   o onion   p play   + - rate
    View        z zoom   m actual size tiled
    History     u undo   U redo
    Text        g glyph and colour the text renderer draws
    Files       s save   w save and install   Esc back to the arts   ^Q quit
    Picker      arrows or pointer choose   Enter take   Esc leave
    """
  end

  defp prompt_row(%{prompt: nil}), do: label("")

  defp prompt_row(%{prompt: {_kind, question}}) do
    horizontal(
      [
        label(question <> ":", style: %{fg: :yellow}),
        text_input(id: :prompt, bind: :prompt_text, on_submit: :prompt_submit, flex: 1)
      ],
      gap: 1
    )
  end

  @impl true
  def handle_event(:swatch, %{x: x, y: y}, %{picker: picker} = state) when picker != nil,
    do: {:ok, pick_swatch(state, {x, y})}

  def handle_event(
        :paint,
        %{x: x, y: y, phase: :start},
        %{screen: :edit, tool: :eyedropper, prompt: nil, picker: nil} = state
      ) do
    case Easel.key_at(state.easel, {x, y}, state.easel.frame) do
      nil -> {:noreply, state}
      "." -> {:ok, %{state | status: "nothing there"}}
      key -> {:ok, %{state | key: key, tool: :brush, status: "took #{key}"}}
    end
  end

  def handle_event(
        :paint,
        %{x: x, y: y, phase: phase},
        %{screen: :edit, playing: false, prompt: nil, picker: nil} = state
      ),
      do: {:ok, painted(state, {x, y}, phase)}

  def handle_event(:paint, _pixel, state), do: {:noreply, state}

  def handle_event(:prompt_submit, _data, %{prompt: {kind, _}} = state) do
    text = String.trim(state.prompt_text)
    Drafter.blur(:prompt)
    {:ok, answered(kind, text, %{state | prompt: nil, prompt_text: ""})}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  @impl true
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}

  def handle_event({:key, :escape}, %{prompt: prompt} = state) when prompt != nil do
    Drafter.blur(:prompt)
    {:ok, %{state | prompt: nil, prompt_text: ""}}
  end

  def handle_event(_event, %{prompt: prompt} = state) when prompt != nil, do: {:noreply, state}

  def handle_event({:key, key}, %{help: from} = state)
      when from != nil and key in [:escape, :"?", :q], do: {:ok, %{state | help: nil}}

  def handle_event(_event, %{help: from} = state) when from != nil, do: {:noreply, state}
  def handle_event({:key, :"?"}, state), do: {:ok, %{state | help: state.screen}}

  def handle_event({:key, key}, %{picker: picker} = state) when picker != nil,
    do: picker_key(key, state)

  def handle_event({:key, key}, %{screen: :arts} = state), do: arts_key(key, state)
  def handle_event({:key, key}, %{screen: :edit} = state), do: edit_key(key, state)
  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def on_message({:easel, :quit}, _state), do: exit(:normal)
  def on_message({:easel, message}, state), do: clicked(message, state)
  def on_message(_message, state), do: state

  @impl true
  def on_timer(:play, %{playing: true} = state) do
    Drafter.set_timeout(div(1000, state.easel.fps), :play)
    %{state | shown: rem(state.shown + 1, length(state.easel.frames))}
  end

  def on_timer(:actual, state) do
    Drafter.set_timeout(@actual_every_ms, :actual)
    actual(state)
  end

  def on_timer(_id, state), do: state

  defp actual(%{screen: :edit} = state),
    do: %{
      state
      | actual:
          ActualSize.sync(state.actual, state.easel, Project.entry(state.project, state.name))
    }

  defp actual(state), do: state

  defp clicked(:help, state), do: %{state | help: state.screen}
  defp clicked(:open, %{screen: :arts} = state), do: open_selected(state)
  defp clicked(:new, %{screen: :arts} = state), do: ask(state, :new_art, "name")
  defp clicked(:derive, %{screen: :arts} = state), do: ask_derive(state)
  defp clicked(:clone, %{screen: :arts} = state), do: ask_clone(state)
  defp clicked(_message, %{screen: :arts} = state), do: state
  defp clicked({:tool, tool}, state), do: tool(state, tool)
  defp clicked({:pick, key}, state), do: %{state | key: key}
  defp clicked({:frame, index}, state), do: change(state, &Easel.select_frame(&1, index))
  defp clicked(:onion, state), do: %{state | onion: not state.onion}
  defp clicked(:tiled, state), do: %{state | tiled: not state.tiled}
  defp clicked(:play, state), do: toggle_play(state)
  defp clicked(:zoom, state), do: next_zoom(state)
  defp clicked(:undo, state), do: change(state, &Easel.undo/1)
  defp clicked(:redo, state), do: change(state, &Easel.redo/1)
  defp clicked(:save, state), do: save(state)
  defp clicked(:install, state), do: state |> save() |> install()
  defp clicked(:arts, state), do: to_arts(state)
  defp clicked(_message, state), do: state

  defp arts_key(:down, state),
    do: {:ok, %{state | selected: min(state.selected + 1, max(length(state.arts) - 1, 0))}}

  defp arts_key(:up, state), do: {:ok, %{state | selected: max(state.selected - 1, 0)}}
  defp arts_key(:enter, state), do: {:ok, open_selected(state)}
  defp arts_key(:n, state), do: {:ok, ask(state, :new_art, "name")}
  defp arts_key(:D, state), do: {:ok, ask_derive(state)}
  defp arts_key(:y, state), do: {:ok, ask_clone(state)}
  defp arts_key(:q, _state), do: {:stop, :normal}
  defp arts_key(_key, state), do: {:noreply, state}

  defp source(%{derived: line}), do: "from " <> String.replace_prefix(line, "from ", "")
  defp source(%{file: file}), do: file

  defp selected_name(state) do
    case Enum.at(state.arts, state.selected) do
      nil -> nil
      art -> art.name
    end
  end

  defp ask_derive(state) do
    case selected_name(state) do
      nil -> %{state | status: "choose an art to derive from first"}
      name -> ask(state, {:derive, name}, "name = from #{name}; ...")
    end
  end

  defp ask_clone(state) do
    case selected_name(state) do
      nil -> %{state | status: "choose an art to clone first"}
      name -> ask(state, {:clone, name}, "clone #{name} as")
    end
  end

  defp open_selected(state) do
    case Enum.at(state.arts, state.selected) do
      nil -> state
      art -> open(state, art.name)
    end
  end

  defp open(state, name) do
    case Project.load(state.project, name) do
      {:ok, easel} -> edit(state, name, easel)
      {:error, reason} -> %{state | status: "could not open #{name}: #{inspect(reason)}"}
    end
  end

  defp edit(state, name, easel) do
    actual(%{
      state
      | screen: :edit,
        name: name,
        easel: easel,
        key: List.first(Easel.keys(easel)),
        anchor: nil,
        preview: nil,
        playing: false,
        shown: 0,
        status: "? shows the keys"
    })
  end

  defp edit_key(:escape, state), do: {:ok, to_arts(state)}
  defp edit_key(:s, state), do: {:ok, save(state)}
  defp edit_key(:w, state), do: {:ok, state |> save() |> install()}
  defp edit_key(:u, state), do: {:ok, change(state, &Easel.undo/1)}
  defp edit_key(:m, state), do: {:ok, clicked(:tiled, state)}
  defp edit_key(:U, state), do: {:ok, change(state, &Easel.redo/1)}
  defp edit_key(:b, state), do: {:ok, tool(state, :brush)}
  defp edit_key(:l, state), do: {:ok, tool(state, :line)}
  defp edit_key(:r, state), do: {:ok, tool(state, :rect)}
  defp edit_key(:R, state), do: {:ok, tool(state, :filled_rect)}
  defp edit_key(:f, state), do: {:ok, tool(state, :fill)}
  defp edit_key(:e, state), do: {:ok, tool(state, :eraser)}
  defp edit_key(:i, state), do: {:ok, tool(state, :eyedropper)}
  defp edit_key(:h, state), do: {:ok, change(state, &Easel.flip(&1, :horizontal))}
  defp edit_key(:v, state), do: {:ok, change(state, &Easel.flip(&1, :vertical))}
  defp edit_key(:t, state), do: {:ok, change(state, &Easel.rotate(&1, 90))}
  defp edit_key(:T, state), do: {:ok, change(state, &Easel.rotate(&1, -90))}
  defp edit_key(:left, state), do: {:ok, change(state, &Easel.shift(&1, -1, 0))}
  defp edit_key(:right, state), do: {:ok, change(state, &Easel.shift(&1, 1, 0))}
  defp edit_key(:up, state), do: {:ok, change(state, &Easel.shift(&1, 0, -1))}
  defp edit_key(:down, state), do: {:ok, change(state, &Easel.shift(&1, 0, 1))}
  defp edit_key(:",", state), do: {:ok, change(state, &Easel.select_frame(&1, &1.frame - 1))}
  defp edit_key(:., state), do: {:ok, change(state, &Easel.select_frame(&1, &1.frame + 1))}
  defp edit_key(:a, state), do: {:ok, change(state, &Easel.add_frame/1)}
  defp edit_key(:d, state), do: {:ok, change(state, &Easel.duplicate_frame/1)}
  defp edit_key(:x, state), do: {:ok, change(state, &Easel.delete_frame/1)}

  defp edit_key(:<, state),
    do: {:ok, change(state, &Easel.move_frame(&1, &1.frame, &1.frame - 1))}

  defp edit_key(:>, state),
    do: {:ok, change(state, &Easel.move_frame(&1, &1.frame, &1.frame + 1))}

  defp edit_key(:o, state), do: {:ok, %{state | onion: not state.onion}}
  defp edit_key(:p, state), do: {:ok, toggle_play(state)}
  defp edit_key(:+, state), do: {:ok, change(state, &Easel.set_fps(&1, &1.fps + 1))}
  defp edit_key(:-, state), do: {:ok, change(state, &Easel.set_fps(&1, max(&1.fps - 1, 1)))}
  defp edit_key(:z, state), do: {:ok, next_zoom(state)}
  defp edit_key(:"[", state), do: {:ok, pick_neighbour(state, -1)}
  defp edit_key(:"]", state), do: {:ok, pick_neighbour(state, 1)}
  defp edit_key(:c, state), do: {:ok, open_picker(state, :add, "New colour")}

  defp edit_key(:C, %{key: key} = state) when key != nil,
    do: {:ok, open_picker(state, :set, "Colour of #{key}")}

  defp edit_key(:"#", state), do: {:ok, ask(state, :add_colour, "key #rrggbb")}

  defp edit_key(:k, %{key: key} = state) when key != nil,
    do: {:ok, ask(state, :rename_key, "new key for #{key}")}

  defp edit_key(:K, %{key: key} = state) when key != nil,
    do: {:ok, change(%{state | key: nil}, &Easel.remove_colour(&1, key))}

  defp edit_key(:g, state), do: {:ok, ask(state, :glyph, "glyph #rrggbb")}

  defp edit_key(key, state) do
    case Enum.find_index(@picks, &(&1 == Atom.to_string(key))) do
      nil -> {:noreply, state}
      index -> {:ok, pick(state, index)}
    end
  end

  defp tool(state, tool) when tool in @tools,
    do: %{state | tool: tool, anchor: nil, preview: nil, status: tool_hint(tool)}

  defp next_zoom(state),
    do: %{
      state
      | zoom: Enum.at(@zooms ++ [hd(@zooms)], Enum.find_index(@zooms, &(&1 == state.zoom)) + 1)
    }

  defp pick(state, index) do
    case Enum.at(Easel.keys(state.easel), index) do
      nil -> state
      key -> %{state | key: key}
    end
  end

  defp pick_neighbour(state, delta) do
    keys = Easel.keys(state.easel)

    case Enum.find_index(keys, &(&1 == state.key)) do
      nil -> pick(state, 0)
      index -> pick(state, Integer.mod(index + delta, length(keys)))
    end
  end

  defp change(state, fun) do
    easel = fun.(state.easel)
    keys = Easel.keys(easel)

    %{
      state
      | easel: easel,
        key: if(state.key in keys, do: state.key, else: List.first(keys)),
        shown: min(state.shown, length(easel.frames) - 1)
    }
  end

  defp painted(state, point, :start),
    do: stroke(%{state | anchor: point, preview: state.easel}, point)

  defp painted(state, point, :drag), do: stroke(state, point)
  defp painted(state, point, :end), do: %{stroke(state, point) | anchor: nil, preview: nil}

  defp stroke(%{key: nil, tool: tool} = state, _point) when tool != :eraser,
    do: %{state | status: "no colour in hand: c picks one"}

  defp stroke(%{tool: :brush} = state, point),
    do: %{state | easel: Easel.paint(state.easel, point, state.key)}

  defp stroke(%{tool: :eraser} = state, point),
    do: %{state | easel: Easel.erase(state.easel, point)}

  defp stroke(%{tool: :fill, anchor: anchor} = state, point) when anchor == point,
    do: %{state | easel: Easel.fill(state.easel, point, state.key)}

  defp stroke(%{tool: :fill} = state, _point), do: state
  defp stroke(%{anchor: nil} = state, _point), do: state

  defp stroke(%{tool: :line} = state, point),
    do: %{state | easel: Easel.line(state.preview, state.anchor, point, state.key)}

  defp stroke(%{tool: :rect} = state, point),
    do: %{state | easel: Easel.rect(state.preview, state.anchor, point, state.key)}

  defp stroke(%{tool: :filled_rect} = state, point),
    do: %{state | easel: Easel.rect(state.preview, state.anchor, point, state.key, fill: true)}

  defp stroke(state, _point), do: state

  defp toggle_play(%{playing: true} = state), do: %{state | playing: false, shown: 0}

  defp toggle_play(state) do
    Drafter.set_timeout(div(1000, state.easel.fps), :play)
    %{state | playing: true, shown: state.easel.frame}
  end

  defp picker_rows(state) do
    palette = Enum.map(state.easel.palette, fn {_key, {r, g, b, _a}} -> {r, g, b} end)
    Swatches.chart() ++ if(palette == [], do: [], else: [palette])
  end

  defp open_picker(state, purpose, title) do
    colour =
      case purpose do
        :set -> state.easel |> Easel.colour(state.key) |> then(fn {r, g, b, _a} -> {r, g, b} end)
        :add -> {255, 255, 255}
      end

    %{
      state
      | picker: %{purpose: purpose, title: title, cursor: {0, 0}, colour: colour},
        status: ""
    }
  end

  defp pick_swatch(state, {x, y}) do
    case state |> picker_rows() |> Enum.at(y, []) |> Enum.at(x) do
      nil -> state
      colour -> %{state | picker: %{state.picker | cursor: {x, y}, colour: colour}}
    end
  end

  defp picker_key(:escape, state), do: {:ok, %{state | picker: nil}}
  defp picker_key(:enter, state), do: {:ok, take_colour(state)}

  defp picker_key(:"#", %{picker: %{purpose: :add}} = state),
    do: {:ok, ask(%{state | picker: nil}, :add_colour, "key #rrggbb")}

  defp picker_key(:"#", state),
    do: {:ok, ask(%{state | picker: nil}, :set_colour, "#rrggbb for #{state.key}")}

  defp picker_key(:left, state), do: {:ok, move_cursor(state, -1, 0)}
  defp picker_key(:right, state), do: {:ok, move_cursor(state, 1, 0)}
  defp picker_key(:up, state), do: {:ok, move_cursor(state, 0, -1)}
  defp picker_key(:down, state), do: {:ok, move_cursor(state, 0, 1)}
  defp picker_key(_key, state), do: {:noreply, state}

  defp move_cursor(%{picker: %{cursor: {x, y}}} = state, dx, dy),
    do: pick_swatch(state, {max(x + dx, 0), max(y + dy, 0)})

  defp take_colour(%{picker: %{purpose: :set, colour: colour}} = state),
    do: change(%{state | picker: nil}, &Easel.set_colour(&1, state.key, colour))

  defp take_colour(%{picker: %{purpose: :add, colour: colour}} = state) do
    case Enum.find(@free_keys, &(&1 not in Easel.keys(state.easel))) do
      nil ->
        %{state | picker: nil, status: "no key left for another colour"}

      key ->
        %{
          change(%{state | picker: nil}, &Easel.add_colour(&1, key, colour))
          | key: key,
            status: "added #{key} #{hex(colour)}"
        }
    end
  end

  defp ask(state, kind, question) do
    Drafter.focus(:prompt)
    %{state | prompt: {kind, question}, prompt_text: ""}
  end

  defp answered(:new_art, "", state), do: state

  defp answered({:derive, from}, text, state) do
    case String.split(text, "=", parts: 2) do
      [name, line] when name != "" ->
        derived(state, String.to_atom(String.trim(name)), String.trim(line))

      [name] when name != "" ->
        derived(state, String.to_atom(String.trim(name)), "from #{from}")

      _blank ->
        state
    end
  end

  defp answered({:clone, from}, "", state),
    do: %{state | status: "#{from} not cloned: no name given"}

  defp answered({:clone, from}, name, state) do
    case Project.clone(state.project, from, String.to_atom(String.trim(name))) do
      {:ok, project} ->
        %{
          state
          | project: project,
            arts: Project.arts(project),
            status: "cloned #{from} as #{String.trim(name)}.pic"
        }

      {:error, reason} ->
        %{state | status: "could not clone: #{inspect(reason)}"}
    end
  end

  defp answered(:new_art, name, state),
    do: edit(state, String.to_atom(name), Project.new_art(state.project))

  defp answered(:add_colour, text, state) do
    case String.split(text, " ", parts: 2) do
      [key, colour] -> added(state, key, colour)
      _other -> %{state | status: "say a key, a space and a colour"}
    end
  end

  defp answered(:set_colour, text, state) do
    change(state, &Easel.set_colour(&1, state.key, text))
  rescue
    ArgumentError -> %{state | status: "not a colour: #{text}"}
  end

  defp answered(:rename_key, to, state) do
    renamed = change(state, &Easel.rename_key(&1, state.key, to))
    if to in Easel.keys(renamed.easel), do: %{renamed | key: to}, else: renamed
  end

  defp answered(:glyph, text, state) do
    case Project.put_entry(state.project, state.name, glyph_fields(text)) do
      {:ok, project} -> %{state | project: project, status: "glyph set"}
      {:error, reason} -> %{state | status: "could not write the manifest: #{inspect(reason)}"}
    end
  rescue
    ArgumentError -> %{state | status: "not a colour: #{text}"}
  end

  defp added(state, key, colour) do
    changed = change(state, &Easel.add_colour(&1, key, colour))

    if key in Easel.keys(changed.easel),
      do: %{changed | key: key},
      else: %{changed | status: "could not add #{inspect(key)}"}
  rescue
    ArgumentError -> %{state | status: "not a colour: #{colour}"}
  end

  defp glyph_fields(text) do
    case String.split(text, " ", parts: 2) do
      [glyph, "#" <> _ = colour] ->
        [
          glyph: two(glyph),
          color: colour |> Linocut.Palette.color() |> then(fn {r, g, b, _} -> {r, g, b} end)
        ]

      [glyph] ->
        [glyph: two(glyph)]

      _other ->
        []
    end
  end

  defp two(glyph), do: glyph |> String.pad_trailing(2) |> String.slice(0, 2)

  defp derived(state, name, line) do
    case Project.derive(state.project, name, line) do
      {:ok, project} ->
        %{state | project: project, arts: Project.arts(project), status: "#{name}: #{line}"}

      {:error, message} when is_binary(message) ->
        %{state | status: "not derived: #{message}"}

      {:error, reason} ->
        %{state | status: "not derived: #{inspect(reason)}"}
    end
  end

  defp save(%{name: name} = state) do
    if Map.has_key?(Project.entry(state.project, name), :derive),
      do: %{
        state
        | status:
            "#{name} is derived: D writes it a new line, y clones it as a picture of its own"
      },
      else: write(state)
  end

  defp write(state) do
    case Project.save(state.project, state.name, state.easel) do
      {:ok, project} ->
        %{
          state
          | project: project,
            arts: Project.arts(project),
            status: "saved #{state.name}.pic"
        }

      {:error, reason} ->
        %{state | status: "could not save: #{inspect(reason)}"}
    end
  end

  defp install(%{atlas: nil} = state),
    do: %{state | status: state.status <> "  (no atlas to install into: start with --atlas)"}

  defp install(state) do
    case Project.install(state.project, state.atlas) do
      {:ok, name} ->
        %{
          state
          | status:
              state.status <>
                "  installed as #{inspect(name)} (#{length(Atlas.arts(Atlas.fetch(name)))} arts)"
        }

      {:error, reason} ->
        %{state | status: "could not install: #{inspect(reason)}"}
    end
  end

  defp to_arts(state),
    do: %{
      state
      | screen: :arts,
        playing: false,
        picker: nil,
        arts: Project.arts(state.project),
        status: "? shows the keys"
    }
end
