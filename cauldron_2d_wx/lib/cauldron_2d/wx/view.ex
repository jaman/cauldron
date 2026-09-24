defmodule Cauldron2D.Wx.View do
  @moduledoc """
  A wx panel that shows a world: the canvas drawn from the sheet around the focus, the
  hud beside or below it if the game sends one, the keys and the pointer as input, the
  sound through the speaker.

      view = Cauldron2D.Wx.View.new(parent, keymap: keymap, steering: [:left, :right], on_over: fn over -> ... end)
      Cauldron2D.Wx.View.join(view, {:socket, url: url, token: token, topic: "world:main", params: %{}})
      Cauldron2D.Wx.View.join(view, {:local, game: MyGame.Web, world: pid, name: "alice", props: %{}})
      Cauldron2D.Wx.View.leave(view)

  ## Options

    * `:keymap` — wx key codes and `{:mouse, button}` to actions, as `Cauldron2D.Wx.Input.new/2` takes
    * `:steering` — the actions the pointer also drives
    * `:size` — the least the canvas is, in pixels, default `{800, 600}`; it grows with the window
    * `:scale` — pixels per sheet pixel, default `1`
    * `:hud` — where the hud rows go: `:right` (default), `:bottom`, or `:none` for no hud panel
    * `:hud_size` — the hud panel's width (right) or height (bottom) in pixels, default `300`
    * `:hud_colours` — `%{background: rgb, text: rgb}` for the hud panel, default a dark panel with light text
    * `:font` — the hud's font in points, default `12`
    * `:on_over` — called with the outcome when the round is over for this player; the
      game draws what it likes then, the canvas draws nothing of its own
    * `:on_closed` — called with the reason when the link ends
    * `:on_refused` — called with the reason when the join is refused
    * `:on_key` — called with the wx key code of a key that went down and means no action
    * `:sound` — `false` for no sound
    * `:input_every` — milliseconds between input messages, default `100`
    * `:pointer` — whether the pointer aims, default `true`; `pointer/2` changes it later
    * `:zoom` — `true` lets the player zoom: `+`/`=` in, `-` out, `0` back to the
      game's scale, the wheel either way, from a tile of 2 pixels (or the whole map in
      view, whichever is larger) to 64; `zoom/2` sets a tile size from outside.
      Default `false`. A whole map that fits in 4096 pixels a side is drawn from one
      bitmap of it at the current size, so zooming out to see all of it costs nothing
      a frame; the sheet at each size is kept for the view's life, its bitmaps in one
      table the painter reads, so a zoom never takes a sheet from under a paint in
      progress. Watching — joined with `spectate` among the link's props or params —
      the view can also be panned: the arrows and a drag with the left button move
      it, the wheel zooms about the pointer, `0` recentres it as well, and a frame
      whose subject is not the one the pan was taken on drops the pan
    * `:on_stats` — called once a second with `%{frames: n, draws: n}`, the frames
      received and the times the canvas was painted in that second
    * `:show_stats` — draw those numbers in the canvas's top left corner, default
      `false`; `show_stats/2` changes it later

  The canvas is cleared to the sheet's void colour. Input goes to the link on every
  change and every `:input_every` ms.
  """

  @behaviour :wx_object

  import Bitwise

  alias Cauldron2D.Net.{Link, Sound}
  alias Cauldron2D.Wx.{Const, Input, Painter, Sheet}

  require Record

  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxKey, Record.extract(:wxKey, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxMouse, Record.extract(:wxMouse, from_lib: "wx/include/wx.hrl"))

  @hud_line 15

  @doc "The world panel under `parent`."
  @spec new(term(), keyword()) :: term()
  def new(parent, opts \\ []), do: :wx_object.start_link(__MODULE__, {parent, opts}, [])

  @doc "Join a world through a link: `{:socket, opts}` or `{:local, opts}`, the options of the link module less `:owner`."
  @spec join(term(), {:socket | :local, keyword()}) :: :ok
  def join(world, link), do: :wx_object.call(world, {:join, link})

  @doc "Leave the world."
  @spec leave(term()) :: :ok
  def leave(world), do: :wx_object.call(world, :leave)

  @doc "Read keys by another keymap from now on, as `new/2`'s `:keymap`; what was held is let go."
  @spec keymap(term(), map()) :: :ok
  def keymap(view, keymap), do: :wx_object.cast(view, {:keymap, keymap})

  @doc "Pause or resume a world of the player's own, through the link."
  @spec pause(term()) :: :ok
  def pause(world), do: :wx_object.cast(world, :pause)

  @doc "The effects and music levels, 0.0 to 1.0."
  @spec levels(term(), number(), number()) :: :ok
  def levels(world, sfx, music), do: :wx_object.cast(world, {:levels, sfx, music})

  @doc "The panel's wx window."
  @spec window(term()) :: term()
  def window(world), do: :wx_object.call(world, :window)

  @doc "Draw tiles `pixels` wide from now on, within the zoom's limits."
  @spec zoom(term(), pos_integer()) :: :ok
  def zoom(view, pixels), do: :wx_object.cast(view, {:zoom, pixels})

  @doc "Whether the frames and draws a second are drawn on the canvas from now on."
  @spec show_stats(term(), boolean()) :: :ok
  def show_stats(view, on?), do: :wx_object.cast(view, {:show_stats, on?})

  @doc "Whether the pointer aims from now on."
  @spec pointer(term(), boolean()) :: :ok
  def pointer(view, on?), do: :wx_object.cast(view, {:pointer, on?})

  @doc "Give the canvas the keyboard."
  @spec focus(term()) :: :ok
  def focus(world), do: :wx_object.cast(world, :focus)

  @impl :wx_object
  def init({parent, opts}) do
    {width, height} = Keyword.get(opts, :size, {800, 600})
    placement = Keyword.get(opts, :hud, :right)
    hud_size = Keyword.get(opts, :hud_size, 300)

    colours =
      Map.merge(
        %{background: {15, 19, 38}, text: {228, 231, 243}},
        Keyword.get(opts, :hud_colours, %{})
      )

    panel = :wxPanel.new(parent, style: Const.wants_chars())

    canvas =
      :wxPanel.new(panel,
        size: {width, height},
        style: Const.wants_chars() ||| Const.full_repaint_on_resize()
      )

    :wxWindow.setBackgroundStyle(canvas, Const.bg_style_paint())
    :wxWindow.setMinSize(canvas, {width, height})

    sizer =
      :wxBoxSizer.new(if(placement == :bottom, do: Const.vertical(), else: Const.horizontal()))

    :wxSizer.add(sizer, canvas, proportion: 1, flag: Const.all() ||| Const.expand(), border: 8)
    scene = :ets.new(__MODULE__, [:set, :public])

    font =
      :wxFont.new(
        Keyword.get(opts, :font, 12),
        Const.teletype(),
        Const.normal(),
        Const.fontweight_normal()
      )

    hud = hud_panel(panel, sizer, placement, hud_size, {width, height}, scene, font, colours)
    :wxPanel.setSizer(panel, sizer)

    for event <- [
          :key_down,
          :key_up,
          :left_down,
          :left_up,
          :right_down,
          :right_up,
          :middle_down,
          :middle_up,
          :motion,
          :mousewheel,
          :kill_focus
        ],
        do: :wxPanel.connect(canvas, event)

    :ets.insert(scene, [{:counts, 0, 0}, {:stats, nil}])

    :wxPanel.connect(canvas, :paint,
      callback: fn _event, _obj ->
        paint_canvas(canvas, scene, font, :wxWindow.getClientSize(canvas))
      end
    )

    state = %{
      panel: panel,
      canvas: canvas,
      hud: hud,
      scale: Keyword.get(opts, :scale, 1),
      zoom?: Keyword.get(opts, :zoom, false),
      pixels: nil,
      pan: {0.0, 0.0},
      subject: nil,
      watching?: false,
      drag: nil,
      png: nil,
      index: nil,
      layer: nil,
      input_every: Keyword.get(opts, :input_every, 100),
      pointer?: Keyword.get(opts, :pointer, true),
      input:
        Input.new(Keyword.get(opts, :keymap, %{}), steering: Keyword.get(opts, :steering, [])),
      link: nil,
      sheet: nil,
      sheets: %{},
      bitmaps: :ets.new(Sheet, [:set, :public]),
      map: nil,
      frame: nil,
      font: font,
      scene: scene,
      sound: if(Keyword.get(opts, :sound, true), do: start_sound(), else: nil),
      callbacks:
        Map.new(Keyword.take(opts, [:on_over, :on_closed, :on_refused, :on_key, :on_stats])),
      show_stats?: Keyword.get(opts, :show_stats, false),
      over: nil,
      ticking?: false
    }

    {panel, state}
  end

  defp hud_panel(_panel, _sizer, :none, _size, _canvas, _scene, _font, _colours), do: nil

  defp hud_panel(panel, sizer, placement, size, {width, height}, scene, font, colours) do
    dimensions = if placement == :bottom, do: {width, size}, else: {size, height}
    hud = :wxPanel.new(panel, size: dimensions)
    :wxWindow.setBackgroundStyle(hud, Const.bg_style_paint())
    :wxWindow.setMinSize(hud, dimensions)
    :wxSizer.add(sizer, hud, flag: Const.all() ||| Const.expand(), border: 8)

    :wxPanel.connect(hud, :paint,
      callback: fn _event, _obj -> paint_hud(hud, scene, font, colours) end
    )

    hud
  end

  defp start_sound do
    {:ok, sound} = Sound.start_link()
    sound
  end

  @impl :wx_object
  def handle_call({:join, {kind, opts}}, _from, state) do
    state = drop_link(state)
    module = link_module(kind)

    unless state.ticking? do
      Process.send_after(self(), :send_input, state.input_every)
      Process.send_after(self(), :stats, 1000)
    end

    state = %{state | ticking?: true}

    case module.start_link([owner: self()] ++ opts) do
      {:ok, link} ->
        {:reply, :ok,
         %{
           state
           | link: {module, link},
             map: nil,
             frame: nil,
             over: nil,
             pan: {0.0, 0.0},
             subject: nil,
             drag: nil,
             watching?: watching?(opts)
         }}

      :ignore ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:leave, _from, state), do: {:reply, :ok, drop_link(state)}
  def handle_call(:window, _from, state), do: {:reply, state.panel, state}

  defp watching?(opts) do
    props = Keyword.get(opts, :props, %{})
    params = Keyword.get(opts, :params, %{})

    Map.get(props, :spectate, false) == true or
      Map.get(params, "spectate", false) in [true, "1", "true"]
  end

  defp link_module(:socket), do: Link.Socket
  defp link_module(:local), do: Link.Local

  defp drop_link(%{link: nil} = state), do: state

  defp drop_link(%{link: {module, link}} = state) do
    if Process.alive?(link), do: module.leave(link)
    %{state | link: nil}
  end

  @impl :wx_object
  def handle_cast(:pause, %{link: {module, link}} = state) do
    module.pause(link)
    {:noreply, state}
  end

  def handle_cast(:pause, state), do: {:noreply, state}

  def handle_cast({:keymap, keymap}, state),
    do: {:noreply, %{state | input: Input.new(keymap, steering: state.input.steering)}}

  def handle_cast({:levels, sfx, music}, %{link: {module, link}} = state) do
    module.levels(link, sfx, music)
    {:noreply, state}
  end

  def handle_cast({:pointer, on?}, state),
    do:
      {:noreply,
       %{
         state
         | pointer?: on?,
           input: if(on?, do: state.input, else: Input.aim(state.input, nil))
       }}

  def handle_cast({:zoom, pixels}, state), do: {:noreply, zoom_to(state, pixels)}

  def handle_cast({:show_stats, on?}, state) do
    unless on?, do: :ets.insert(state.scene, {:stats, nil})
    {:noreply, %{state | show_stats?: on?}}
  end

  def handle_cast(:focus, state) do
    :wxWindow.setFocus(state.canvas)
    {:noreply, state}
  end

  def handle_cast(_message, state), do: {:noreply, state}

  @impl :wx_object
  def handle_info({:cauldron_link, :sheet, index, png}, state) do
    pixels = state.pixels || index.tile * state.scale
    {:noreply, %{state | index: index, png: png, sheets: %{}} |> resheet(pixels) |> staged()}
  end

  def handle_info({:cauldron_link, :map, map}, state),
    do: {:noreply, %{state | map: map} |> relayer() |> staged()}

  def handle_info({:cauldron_link, :frame, frame}, state) do
    :ets.update_counter(state.scene, :counts, {2, 1})
    state = staged(%{state | frame: frame} |> followed())
    :wxWindow.refresh(state.canvas, eraseBackground: false)
    if state.hud, do: :wxWindow.refresh(state.hud, eraseBackground: false)

    case frame.over do
      nil -> {:noreply, state}
      over when state.over == nil -> callback(state, :on_over, over)
      _seen -> {:noreply, state}
    end
    |> then(fn {:noreply, s} -> {:noreply, %{s | over: frame.over}} end)
  end

  def handle_info({:cauldron_link, :pcm, chunk}, %{sound: sound} = state) when sound != nil do
    Sound.play(sound, chunk)
    {:noreply, state}
  end

  def handle_info(
        {:cauldron_link, :audio, %{rate: rate, channels: channels}},
        %{sound: sound} = state
      )
      when sound != nil do
    Sound.format(sound, rate, channels)
    {:noreply, state}
  end

  def handle_info({:cauldron_link, :joined}, state), do: {:noreply, state}

  def handle_info({:cauldron_link, :refused, reason}, state),
    do: callback(%{state | link: nil}, :on_refused, reason)

  def handle_info({:cauldron_link, :closed, reason}, state),
    do: callback(%{state | link: nil}, :on_closed, reason)

  def handle_info(:send_input, state) do
    Process.send_after(self(), :send_input, state.input_every)
    {:noreply, push_input(state)}
  end

  def handle_info(:stats, state) do
    Process.send_after(self(), :stats, 1000)
    [{:counts, frames, draws}] = :ets.lookup(state.scene, :counts)

    :ets.insert(state.scene, [
      {:counts, 0, 0},
      {:stats, if(state.show_stats?, do: "#{frames} frames/s  #{draws} draws/s")}
    ])

    callback(state, :on_stats, %{frames: frames, draws: draws})
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp staged(state) do
    :ets.insert(state.scene, {:scene, state.sheet, state.map, shown(state), state.layer})
    state
  end

  defp shown(%{frame: nil}), do: nil

  defp shown(%{frame: %{focus: {fx, fy}} = frame, pan: {px, py}}),
    do: %{frame | focus: {fx + px, fy + py}}

  defp followed(%{frame: %{subject: subject}, subject: subject} = state), do: state

  defp followed(%{frame: %{subject: subject}} = state),
    do: %{state | pan: {0.0, 0.0}, subject: subject}

  defp followed(state), do: state

  defp pan_by(%{pan: {px, py}} = state, {dx, dy}) do
    state = %{state | pan: {px + dx, py + dy}} |> staged()
    :wxWindow.refresh(state.canvas, eraseBackground: false)
    state
  end

  defp zoom_about(
         %{watching?: true, frame: frame, map: map, sheet: %Sheet{} = sheet} = state,
         factor,
         point
       )
       when frame != nil and map != nil do
    from = Sheet.pixels(sheet)
    zoomed = zoom_by(state, factor)
    to = Sheet.pixels(zoomed.sheet)
    {fx, fy} = frame.focus

    {nx, ny} =
      Painter.zoom_about(
        shown(state),
        map,
        :wxWindow.getClientSize(state.canvas),
        from,
        to,
        point
      )

    if to == from, do: zoomed, else: pan_by(%{zoomed | pan: {0.0, 0.0}}, {nx - fx, ny - fy})
  end

  defp zoom_about(state, factor, _point), do: zoom_by(state, factor)

  @pan_keys %{314 => {-1, 0}, 315 => {0, -1}, 316 => {1, 0}, 317 => {0, 1}}
  @pan_pixels 64

  @zoom_steps [2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]
  @layer_limit 4096

  defp zoom_to(%{index: nil} = state, _pixels), do: state

  defp zoom_to(state, pixels) do
    {width, height} = :wxWindow.getClientSize(state.canvas)
    whole = if state.map, do: min(width / state.map.width, height / state.map.height), else: 0
    least = Enum.find(@zoom_steps, 64, &(&1 >= whole))
    pixels = pixels |> max(least) |> min(64)
    if pixels == state.pixels, do: state, else: state |> resheet(pixels) |> staged()
  end

  defp zoom_by(state, factor) do
    current = state.pixels || (state.index && state.index.tile * state.scale) || 16
    wanted = current * factor

    next =
      if factor > 1,
        do: Enum.find(@zoom_steps, 64, &(&1 >= wanted - 0.01)),
        else: @zoom_steps |> Enum.reverse() |> Enum.find(2, &(&1 <= wanted + 0.01))

    zoom_to(state, next)
  end

  defp resheet(state, pixels) do
    sheet =
      Map.get_lazy(state.sheets, pixels, fn ->
        Sheet.load(state.index, state.png, pixels / state.index.tile, bitmaps: state.bitmaps)
      end)

    %{state | sheet: sheet, sheets: Map.put(state.sheets, pixels, sheet), pixels: pixels}
    |> relayer()
  end

  defp relayer(%{sheet: %Sheet{} = sheet, map: map} = state) when map != nil do
    pixels = Sheet.pixels(sheet)

    if map.width * pixels <= @layer_limit and map.height * pixels <= @layer_limit do
      bitmap = :wxBitmap.new(map.width * pixels, map.height * pixels)
      dc = :wxMemoryDC.new(bitmap)
      :wxDC.setBackground(dc, :wxBrush.new(sheet.void))
      :wxDC.clear(dc)

      for {index, x, y} <- Painter.layer_blits(map, pixels, except: Sheet.animated(sheet)),
          tile = Sheet.bitmap(sheet, index),
          tile != nil,
          do: :wxDC.drawBitmap(dc, tile, {x, y}, useMask: true)

      :wxMemoryDC.destroy(dc)
      %{state | layer: bitmap}
    else
      %{state | layer: nil}
    end
  end

  defp relayer(state), do: %{state | layer: nil}

  defp callback(state, name, argument) do
    case Map.get(state.callbacks, name) do
      nil -> :ok
      fun -> fun.(argument)
    end

    {:noreply, state}
  end

  defp push_input(%{link: {module, link}} = state) do
    module.input(link, Input.state(state.input))
    state
  end

  defp push_input(state), do: state

  @impl :wx_object
  def handle_event(wx(event: wxKey(type: :key_down, keyCode: code)), %{zoom?: true} = state)
      when code in [?=, ?+, 388] do
    {:noreply, zoom_by(state, 1.5)}
  end

  def handle_event(wx(event: wxKey(type: :key_down, keyCode: code)), %{zoom?: true} = state)
      when code in [?-, 390] do
    {:noreply, zoom_by(state, 1 / 1.5)}
  end

  def handle_event(wx(event: wxKey(type: :key_down, keyCode: code)), %{zoom?: true} = state)
      when code in [?0, 380] do
    {:noreply,
     state
     |> zoom_to(state.index.tile * state.scale)
     |> Map.put(:pan, {0.0, 0.0})
     |> pan_by({0.0, 0.0})}
  end

  def handle_event(
        wx(event: wxKey(type: :key_down, keyCode: code)),
        %{watching?: true, sheet: %Sheet{} = sheet} = state
      )
      when is_map_key(@pan_keys, code) do
    {dx, dy} = Map.fetch!(@pan_keys, code)
    pixels = Sheet.pixels(sheet)
    {:noreply, pan_by(state, {dx * @pan_pixels / pixels, dy * @pan_pixels / pixels})}
  end

  def handle_event(wx(event: wxKey(type: :key_down, keyCode: code)), state) do
    :wxWindow.setFocus(state.canvas)
    {input, handled?} = Input.press(state.input, code)
    unless handled?, do: callback(state, :on_key, code)
    {:noreply, changed(state, input, handled?)}
  end

  def handle_event(
        wx(event: wxMouse(type: :mousewheel, wheelRotation: rotation, x: x, y: y)),
        %{zoom?: true} = state
      ) do
    {:noreply, zoom_about(state, if(rotation > 0, do: 1.5, else: 1 / 1.5), {x, y})}
  end

  def handle_event(wx(event: wxMouse(type: :mousewheel)), state), do: {:noreply, state}

  def handle_event(wx(event: wxKey(type: :key_up, keyCode: code)), state) do
    {input, handled?} = Input.release(state.input, code)
    {:noreply, changed(state, input, handled?)}
  end

  def handle_event(
        wx(event: wxMouse(type: :motion, x: x, y: y, leftDown: true)),
        %{watching?: true, drag: {fx, fy}, sheet: %Sheet{} = sheet} = state
      ) do
    pixels = Sheet.pixels(sheet)
    {:noreply, pan_by(%{state | drag: {x, y}}, {(fx - x) / pixels, (fy - y) / pixels})}
  end

  def handle_event(wx(event: wxMouse(type: :motion, x: x, y: y)), %{pointer?: true} = state) do
    {:noreply, %{state | input: Input.aim(state.input, world_at(state, {x, y}))}}
  end

  def handle_event(wx(event: wxMouse(type: :motion)), state), do: {:noreply, state}

  def handle_event(wx(event: wxMouse(type: :left_down, x: x, y: y)), %{watching?: true} = state) do
    :wxWindow.setFocus(state.canvas)
    {:noreply, %{state | drag: {x, y}}}
  end

  def handle_event(wx(event: wxMouse(type: :left_up)), %{watching?: true} = state),
    do: {:noreply, %{state | drag: nil}}

  def handle_event(wx(event: wxMouse(type: type, x: x, y: y)), state)
      when type in [:left_down, :right_down, :middle_down] do
    :wxWindow.setFocus(state.canvas)
    input = state.input |> Input.aim(world_at(state, {x, y})) |> Input.button(button(type), true)
    {:noreply, changed(state, input, true)}
  end

  def handle_event(wx(event: wxMouse(type: type)), state)
      when type in [:left_up, :right_up, :middle_up] do
    {:noreply, changed(state, Input.button(state.input, button(type), false), true)}
  end

  def handle_event(wx(event: {:wxFocus, :kill_focus, _}), state),
    do: {:noreply, changed(state, Input.drop(state.input), true)}

  def handle_event(_event, state), do: {:noreply, state}

  defp button(:left_down), do: :left
  defp button(:left_up), do: :left
  defp button(:right_down), do: :right
  defp button(:right_up), do: :right
  defp button(_middle), do: :middle

  defp changed(state, input, false), do: %{state | input: input}
  defp changed(state, input, true), do: push_input(%{state | input: input})

  defp world_at(%{frame: frame, map: map, sheet: %Sheet{} = sheet} = state, point)
       when frame != nil and map != nil,
       do:
         Painter.world_at(
           shown(state),
           map,
           :wxWindow.getClientSize(state.canvas),
           Sheet.pixels(sheet),
           point
         )

  defp world_at(_state, _point), do: nil

  defp scene(table) do
    case :ets.lookup(table, :scene) do
      [{:scene, sheet, map, frame, layer}] -> {sheet, map, frame, layer}
      [] -> {nil, nil, nil, nil}
    end
  end

  defp paint_canvas(canvas, table, font, size) do
    {sheet, map, frame, layer} = scene(table)
    :ets.update_counter(table, :counts, {3, 1})
    dc = :wxBufferedPaintDC.new(canvas)
    :wxDC.setBackground(dc, :wxBrush.new(if(sheet, do: sheet.void, else: {0, 0, 0})))
    :wxDC.clear(dc)
    draw_world(dc, sheet, map, frame, layer, size)
    draw_labels(dc, sheet, map, frame, size)
    draw_stats(dc, font, :ets.lookup(table, :stats))
    :wxBufferedPaintDC.destroy(dc)
    :ok
  end

  defp draw_stats(dc, font, [{:stats, text}]) when is_binary(text) do
    :wxDC.setFont(dc, font)
    :wxDC.setTextForeground(dc, {255, 255, 255})
    :wxDC.drawText(dc, text, {6, 4})
  end

  defp draw_stats(_dc, _font, _none), do: :ok

  defp draw_labels(dc, %Sheet{} = sheet, map, %{labels: [_ | _] = labels} = frame, size)
       when map != nil do
    pixels = Sheet.pixels(sheet)

    for {text, x, y, colour, scale} <- labels,
        {px, py} <- Painter.label_blits(frame, map, size, pixels, {x, y}) do
      :wxDC.setFont(
        dc,
        :wxFont.new(
          max(6, round(pixels * 0.45 * scale)),
          Const.teletype(),
          Const.normal(),
          Const.fontweight_normal()
        )
      )

      :wxDC.setTextForeground(dc, label_colour(colour))
      :wxDC.drawText(dc, text, {px, py})
    end

    :ok
  end

  defp draw_labels(_dc, _sheet, _map, _frame, _size), do: :ok

  defp label_colour("#" <> hex),
    do: hex |> Base.decode16!(case: :mixed) |> then(fn <<r, g, b>> -> {r, g, b} end)

  defp label_colour(_none), do: {255, 255, 255}

  defp draw_world(dc, %Sheet{} = sheet, map, frame, nil, size) when map != nil and frame != nil do
    now = System.monotonic_time(:millisecond)

    for {index, x, y} <- Painter.blits(frame, map, size, Sheet.pixels(sheet)),
        bitmap = Sheet.bitmap_at(sheet, index, now),
        bitmap != nil do
      :wxDC.drawBitmap(dc, bitmap, {x, y}, useMask: true)
    end

    :ok
  end

  defp draw_world(dc, %Sheet{} = sheet, map, frame, layer, size)
       when map != nil and frame != nil do
    pixels = Sheet.pixels(sheet)
    now = System.monotonic_time(:millisecond)

    for {x, y} <- Painter.layer_offsets(frame, map, size, pixels),
        do: :wxDC.drawBitmap(dc, layer, {x, y})

    for {index, x, y} <-
          Painter.cell_blits(frame, map, size, pixels, Sheet.animated(sheet)) ++
            Painter.mover_blits(frame, map, size, pixels),
        bitmap = Sheet.bitmap_at(sheet, index, now),
        bitmap != nil do
      :wxDC.drawBitmap(dc, bitmap, {x, y}, useMask: true)
    end

    :ok
  end

  defp draw_world(_dc, _sheet, _map, _frame, _layer, _size), do: :ok

  defp paint_hud(hud, table, font, colours) do
    {_sheet, _map, frame, _layer} = scene(table)
    dc = :wxBufferedPaintDC.new(hud)
    :wxDC.setBackground(dc, :wxBrush.new(colours.background))
    :wxDC.clear(dc)
    :wxDC.setFont(dc, font)

    frame |> hud_rows() |> Enum.with_index() |> Enum.each(&draw_row(dc, &1, colours.text))
    :wxBufferedPaintDC.destroy(dc)
  end

  defp draw_row(dc, {row, index}, default) do
    Enum.reduce(row, 8, fn {text, colour}, x ->
      draw_run(dc, text, rgb(colour, default), {x, 6 + index * @hud_line})
    end)
  end

  defp draw_run(dc, text, colour, {x, y}) do
    :wxDC.setTextForeground(dc, colour)
    :wxDC.drawText(dc, text, {x, y})
    {width, _height} = :wxDC.getTextExtent(dc, text)
    x + width
  end

  defp hud_rows(%{hud: hud}), do: hud
  defp hud_rows(nil), do: []

  defp rgb(nil, default), do: default

  defp rgb("#" <> hex, _default),
    do: hex |> Base.decode16!(case: :mixed) |> then(fn <<r, g, b>> -> {r, g, b} end)

  defp rgb({_, _, _} = rgb, _default), do: rgb

  @impl :wx_object
  def terminate(_reason, state) do
    drop_link(state)
    :ok
  end
end
