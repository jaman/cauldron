defmodule Cauldron2D.Wx.View do
  @moduledoc """
  A wx panel that shows a world: its picture scaled to the canvas, the hud beside or
  below it if the game sends one, the keys, the pointer and the mouse as input, the
  sound through the speaker. The picture is the one every front end shows — the
  scene drawn by `Cauldron2D.Draw`, here through the link — so the game's layers,
  projections, `:screen`, `:outlines` and menu look as they do in the terminal.

      view = Cauldron2D.Wx.View.new(parent, on_go: fn to -> ... end)
      Cauldron2D.Wx.View.join(view, {:socket, url: url, token: token, topic: "world:main", params: %{}})
      Cauldron2D.Wx.View.join(view, {:local, game: MyGame.Client, world: pid, name: "alice", props: %{}})
      Cauldron2D.Wx.View.leave(view)

  Without a link the view shows what `show/2` gives it — a picture its owner drew, such
  as a game's title front — and hands every key to `:on_key`.

  The pane — how many of the atlas's tiles the canvas shows across and down at zoom 1 —
  is the canvas's size over the tile's size in pixels times `:scale`; the view tells
  the link whenever it changes, and the picture comes back drawn over it. Keys reach the
  link as they go down and up, the mouse's buttons, wheel and moves with the pointer as
  fractions of the picture, and the controllers' events as they come: the session reads
  them as every front end's are read (`Cauldron.Client.Controls`, the client's own keys
  and the game's menu first), so the view holds no keymap of its own.

  In a game with a chat, the hud panel lists the last messages of the world's room
  under the hud rows; the game's talk key opens a line there, typed into until `Enter`
  says it or `Esc` drops it, the game's keys standing idle meanwhile.

  ## Options

    * `:size` — the least the canvas is, in pixels, default `{800, 600}`; it grows with the window
    * `:scale` — screen pixels a picture pixel, default `2`
    * `:hud` — where the hud rows go: `:right` (default), `:bottom`, or `:none` for no hud panel
    * `:hud_size` — the hud panel's width (right) or height (bottom) in pixels, default `300`
    * `:hud_colours` — `%{background: rgb, text: rgb}` for the hud panel, default a dark panel with light text
    * `:font` — the hud's font in points, default `12`
    * `:on_over` — called with the outcome when the round is over for this player
    * `:on_closed` — called with the reason when the link ends
    * `:on_refused` — called with the reason when the join is refused
    * `:on_go` — called with `:lobby`, `:settings` or `:title` when the game's menu or
      the client's keys send the player there
    * `:on_settings` — called with the player's settings when the game's menu changed them
    * `:on_key` — called with the wx key code of every key that goes down while no link is joined
    * `:on_pad` — called with each controller button pressed while no link is joined
    * `:on_world` — called with the new world's id when the world moved the player to another
    * `:controllers` — whether the view reads this machine's game controllers (`Gamepad`), default `true`
    * `:sound` — `false` for no sound
    * `:on_stats` — called once a second with `%{frames: n, draws: n}`, the pictures
      received and the times the canvas was painted in that second
    * `:show_stats` — draw those numbers in the canvas's top left corner, default
      `false`; `show_stats/2` changes it later
  """

  @behaviour :wx_object

  import Bitwise

  alias Cauldron.Client.Hud
  alias Cauldron.Net.{Link, Sound}
  alias Cauldron2D.{Draw, Raster, Surface}
  alias Cauldron2D.Wx.{Const, Keys}

  require Record

  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxKey, Record.extract(:wxKey, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxMouse, Record.extract(:wxMouse, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxSize, Record.extract(:wxSize, from_lib: "wx/include/wx.hrl"))

  @hud_line 15
  @move_ms 33
  @chat_kept 12
  @said_most 500
  @default_tile 16
  @pans %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}

  @doc "The world panel under `parent`."
  @spec new(term(), keyword()) :: term()
  def new(parent, opts \\ []), do: :wx_object.start_link(__MODULE__, {parent, opts}, [])

  @doc """
  Join a world through a link: `{:socket, opts}` or `{:local, opts}`, the options of the
  link module less `:owner`; the `:drawer` is `Cauldron2D.Net.Drawer` unless given. Option `:opening` is rows of runs (`Cauldron.Client.Hud`)
  drawn centred on the canvas until the world's first picture arrives; default none.
  Option `:watching` — `true` for a player who joined to watch — makes the arrow keys
  and a drag with the left button move the view (the link's `pan/2`) instead of
  reaching the world; default `false`.
  """
  @spec join(term(), {:socket | :local, keyword()}, keyword()) :: :ok | {:error, term()}
  def join(world, link, opts \\ []), do: :wx_object.call(world, {:join, link, opts})

  @doc "Leave the world."
  @spec leave(term()) :: :ok
  def leave(world), do: :wx_object.call(world, :leave)

  @doc "Show `raster` scaled to the canvas, for a picture drawn without a link."
  @spec show(term(), Raster.t()) :: :ok
  def show(view, raster), do: :wx_object.cast(view, {:show, raster})

  @doc "The tiles across and down the canvas shows at zoom 1, for an atlas whose tile is `tile` pixels."
  @spec pane(term(), pos_integer()) :: {pos_integer(), pos_integer()}
  def pane(view, tile), do: :wx_object.call(view, {:pane, tile})

  @doc "The player's settings changed beside the world — `:preset`, `:pointer`, `:fps` — told to the link."
  @spec configure(term(), map()) :: :ok
  def configure(view, changes), do: :wx_object.cast(view, {:configure, changes})

  @doc "Pause or resume a world of the player's own, through the link."
  @spec pause(term()) :: :ok
  def pause(world), do: :wx_object.cast(world, :pause)

  @doc "The effects and music levels, 0.0 to 1.0."
  @spec levels(term(), number(), number()) :: :ok
  def levels(world, sfx, music), do: :wx_object.cast(world, {:levels, sfx, music})

  @doc "The panel's wx window."
  @spec window(term()) :: term()
  def window(world), do: :wx_object.call(world, :window)

  @doc "Whether the frames and draws a second are drawn on the canvas from now on."
  @spec show_stats(term(), boolean()) :: :ok
  def show_stats(view, on?), do: :wx_object.cast(view, {:show_stats, on?})

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
          :kill_focus,
          :size,
          :char
        ],
        do: :wxPanel.connect(canvas, event)

    :ets.insert(scene, [
      {:counts, 0, 0},
      {:stats, nil},
      {:bitmap, nil},
      {:void, {0, 0, 0}},
      {:status, nil},
      {:opening, []},
      {:chat, {[], nil}}
    ])

    :wxPanel.connect(canvas, :paint,
      callback: fn _event, _obj -> paint_canvas(canvas, scene, font) end
    )

    state = %{
      panel: panel,
      canvas: canvas,
      hud: hud,
      scale: Keyword.get(opts, :scale, 2),
      tile: @default_tile,
      pane: nil,
      raster: nil,
      drawn_scene: nil,
      overlay: nil,
      down: %{},
      moved_at: 0,
      link: nil,
      font: font,
      scene: scene,
      sound: if(Keyword.get(opts, :sound, true), do: start_sound(), else: nil),
      callbacks:
        Map.new(
          Keyword.take(opts, [
            :on_over,
            :on_closed,
            :on_refused,
            :on_key,
            :on_stats,
            :on_go,
            :on_settings,
            :on_pad,
            :on_world
          ])
        ),
      controllers: controllers(Keyword.get(opts, :controllers, true)),
      chat: [],
      typing: nil,
      show_stats?: Keyword.get(opts, :show_stats, false),
      over: nil,
      ticking?: false,
      watching?: false,
      drag: nil
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

  defp controllers(false), do: false

  defp controllers(true) do
    if Gamepad.available?(), do: Gamepad.start_link(sink: self())
    true
  end

  defp start_sound do
    {:ok, sound} = Sound.start_link()
    sound
  end

  @impl :wx_object
  def handle_call({:join, {kind, opts}, join_opts}, _from, state) do
    state = drop_link(state)
    module = link_module(kind)

    unless state.ticking?, do: Process.send_after(self(), :stats, 1000)

    :ets.insert(state.scene, [
      {:bitmap, nil},
      {:status, nil},
      {:opening, Keyword.get(join_opts, :opening, [])}
    ])

    state = %{
      state
      | ticking?: true,
        raster: nil,
        drawn_scene: nil,
        overlay: nil,
        pane: nil,
        over: nil,
        watching?: Keyword.get(join_opts, :watching, false),
        drag: nil
    }

    case module.start_link(
           [owner: self()] ++ Keyword.put_new(opts, :drawer, Cauldron2D.Net.Drawer)
         ) do
      {:ok, link} -> {:reply, :ok, %{state | link: {module, link}}}
      :ignore -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:leave, _from, state), do: {:reply, :ok, drop_link(state)}
  def handle_call(:window, _from, state), do: {:reply, state.panel, state}

  def handle_call({:pane, tile}, _from, state) do
    state = %{state | tile: tile}
    {:reply, pane_of(state), state}
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

  def handle_cast({:show, raster}, state), do: {:noreply, pictured(state, raster)}

  def handle_cast({:configure, changes}, %{link: {module, link}} = state) do
    module.configure(link, changes)
    {:noreply, state}
  end

  def handle_cast({:configure, _changes}, state), do: {:noreply, state}

  def handle_cast({:levels, sfx, music}, %{link: {module, link}} = state) do
    module.levels(link, sfx, music)
    {:noreply, state}
  end

  def handle_cast({:levels, _sfx, _music}, state), do: {:noreply, state}

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
  def handle_info({:cauldron_link, :sheet, sheet, _png}, state) do
    :ets.insert(state.scene, {:void, sheet.void})
    {:noreply, repaned(%{state | tile: sheet.tile})}
  end

  def handle_info({:cauldron_link, :drawing, _drawing}, state), do: {:noreply, repaned(state)}

  def handle_info({:gamepad, event}, %{link: {module, link}} = state) do
    module.pad_event(link, event)
    {:noreply, state}
  end

  def handle_info({:gamepad, %{type: :button, button: button, pressed: true}}, state),
    do: callback(state, :on_pad, button)

  def handle_info({:gamepad, _event}, state), do: {:noreply, state}

  def handle_info({:cauldron_link, :status, status}, state) do
    :ets.insert(state.scene, {:status, status})
    if state.hud, do: :wxWindow.refresh(state.hud, eraseBackground: false)

    case status.over do
      nil -> {:noreply, %{state | over: nil}}
      over when state.over == nil -> callback(%{state | over: over}, :on_over, over)
      _seen -> {:noreply, state}
    end
  end

  def handle_info({:cauldron_link, :picture, raster}, state) do
    :ets.update_counter(state.scene, :counts, {2, 1})
    :ets.insert(state.scene, {:opening, []})
    {:noreply, pictured(state, raster)}
  end

  def handle_info({:cauldron_link, :scene, view}, state) do
    :ets.update_counter(state.scene, :counts, {2, 1})
    :ets.insert(state.scene, {:opening, []})
    {:noreply, scened(%{state | drawn_scene: view})}
  end

  def handle_info({:cauldron_link, :overlay, overlay}, state) do
    state = %{state | overlay: overlay}
    {:noreply, if(state.drawn_scene, do: scened(state), else: state)}
  end

  def handle_info({:cauldron_link, :chat_history, messages}, state),
    do: {:noreply, chatted(%{state | chat: Enum.take(messages, -@chat_kept)})}

  def handle_info({:cauldron_link, :chat, message}, state),
    do: {:noreply, chatted(%{state | chat: Enum.take(state.chat ++ [message], -@chat_kept)})}

  def handle_info({:cauldron_link, :talk}, state), do: {:noreply, chatted(%{state | typing: ""})}

  def handle_info({:cauldron_link, :world, id}, state) do
    :ets.insert(state.scene, {:bitmap, nil})
    callback(%{state | raster: nil, drawn_scene: nil, overlay: nil, over: nil}, :on_world, id)
  end

  def handle_info({:cauldron_link, :go, to}, state), do: callback(state, :on_go, to)

  def handle_info({:cauldron_link, :settings, settings}, state),
    do: callback(state, :on_settings, settings)

  def handle_info({:cauldron_link, :clipboard, text}, state) do
    clipboard = :wxClipboard.get()

    if :wxClipboard.open(clipboard) do
      :wxClipboard.setData(clipboard, :wxTextDataObject.new(text: String.to_charlist(text)))
      :wxClipboard.close(clipboard)
    end

    {:noreply, state}
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

  defp pane_of(state) do
    {width, height} = :wxWindow.getClientSize(state.canvas)
    pixels = state.tile * state.scale
    {max(1, round(width / pixels)), max(1, round(height / pixels))}
  end

  defp repaned(%{link: {module, link}} = state) do
    pane = pane_of(state)
    if pane != state.pane, do: module.pane(link, pane)
    %{state | pane: pane}
  end

  defp repaned(state), do: state

  defp chatted(state) do
    :ets.insert(state.scene, {:chat, {state.chat, state.typing}})
    if state.hud, do: :wxWindow.refresh(state.hud, eraseBackground: false)
    state
  end

  defp scened(%{pane: nil} = state), do: state

  defp scened(state) do
    case Draw.picture(state.drawn_scene, state.pane) do
      nil -> state
      raster -> pictured(state, overlaid(raster, state.overlay))
    end
  end

  defp overlaid(raster, %FrenchCurve.Raster{width: width, height: height} = overlay)
       when raster.width == width and raster.height == height,
       do: Surface.stack(raster, overlay)

  defp overlaid(raster, _overlay), do: raster

  defp pictured(state, raster) do
    # A still frame is already on the canvas; do not make and scale a new bitmap.
    if state.raster == raster do
      state
    else
      old = lookup(state.scene, :bitmap)
      :ets.insert(state.scene, {:bitmap, bitmap(raster, :wxWindow.getClientSize(state.canvas))})
      :wxWindow.refresh(state.canvas, eraseBackground: false)
      # The bitmap is a native resource; letting every frame wait for the GC is how a
      # window at 30 fps grows to gigabytes.
      case old do
        {bitmap, _at} -> :wxBitmap.destroy(bitmap)
        nil -> :ok
        bitmap -> :wxBitmap.destroy(bitmap)
      end

      %{state | raster: raster}
    end
  end

  defp bitmap(%FrenchCurve.Raster{width: width, height: height} = raster, {canvas_w, canvas_h}) do
    rgb = for <<r, g, b, _a <- Raster.to_rgba_binary(raster)>>, into: <<>>, do: <<r, g, b>>
    image = :wxImage.new(width, height, rgb)

    scale = min(canvas_w / width, canvas_h / height)
    shown_w = max(1, round(width * scale))
    shown_h = max(1, round(height * scale))

    scaled =
      :wxImage.scale(image, shown_w, shown_h, quality: Const.image_quality_nearest())

    bitmap = :wxBitmap.new(scaled)
    :wxImage.destroy(scaled)
    :wxImage.destroy(image)
    {bitmap, {div(canvas_w - shown_w, 2), div(canvas_h - shown_h, 2)}}
  end

  defp callback(state, name, argument) do
    case Map.get(state.callbacks, name) do
      nil -> :ok
      fun -> fun.(argument)
    end

    {:noreply, state}
  end

  @impl :wx_object
  def handle_event(wx(event: wxSize()), state) do
    state = repaned(state)

    cond do
      state.drawn_scene -> {:noreply, scened(state)}
      state.raster -> {:noreply, pictured(state, state.raster)}
      true -> {:noreply, state}
    end
  end

  def handle_event(wx(event: wxKey(type: :key_down, keyCode: code)), %{typing: text} = state)
      when text != nil do
    {:noreply, typed(state, code)}
  end

  def handle_event(wx(event: wxKey(type: :char, uniChar: char)), %{typing: text} = state)
      when text != nil and char >= 32 and char != 127 do
    {:noreply, chatted(%{state | typing: String.slice(text <> <<char::utf8>>, 0, @said_most)})}
  end

  def handle_event(wx(event: wxKey(type: :char)), state), do: {:noreply, state}

  def handle_event(wx(event: wxKey(type: :key_down, keyCode: code) = key), state) do
    :wxWindow.setFocus(state.canvas)
    {:noreply, key_down(state, code, key)}
  end

  def handle_event(wx(event: wxKey(type: :key_up, keyCode: code) = key), state),
    do: {:noreply, key_up(state, code, key)}

  def handle_event(
        wx(event: wxMouse(type: :mousewheel, wheelRotation: rotation, x: x, y: y)),
        state
      ) do
    moused(state, %{type: :scroll, direction: if(rotation > 0, do: :up, else: :down)}, {x, y})
    {:noreply, state}
  end

  def handle_event(wx(event: wxMouse(type: :motion, x: x, y: y)), %{drag: {dx, dy}} = state) do
    panned(state, fraction(state, {dx - x, dy - y}))
    {:noreply, %{state | drag: {x, y}}}
  end

  def handle_event(wx(event: wxMouse(type: :motion, x: x, y: y)), state) do
    now = System.monotonic_time(:millisecond)

    if now - state.moved_at >= @move_ms do
      moused(state, %{type: :move}, {x, y})
      {:noreply, %{state | moved_at: now}}
    else
      {:noreply, state}
    end
  end

  def handle_event(wx(event: wxMouse(type: :left_down, x: x, y: y)), %{watching?: true} = state) do
    :wxWindow.setFocus(state.canvas)
    {:noreply, %{state | drag: {x, y}}}
  end

  def handle_event(wx(event: wxMouse(type: :left_up)), %{drag: {_x, _y}} = state),
    do: {:noreply, %{state | drag: nil}}

  def handle_event(wx(event: wxMouse(type: type, x: x, y: y)), state)
      when type in [:left_down, :right_down, :middle_down] do
    :wxWindow.setFocus(state.canvas)
    moused(state, %{type: :mouse_down, button: button(type)}, {x, y})
    {:noreply, state}
  end

  def handle_event(wx(event: wxMouse(type: type, x: x, y: y)), state)
      when type in [:left_up, :right_up, :middle_up] do
    moused(state, %{type: :mouse_up, button: button(type)}, {x, y})
    {:noreply, state}
  end

  def handle_event(wx(event: {:wxFocus, :kill_focus, _}), state), do: {:noreply, let_go(state)}

  def handle_event(_event, state), do: {:noreply, state}

  defp typed(%{link: {module, link}} = state, 13) do
    if String.trim(state.typing) != "", do: module.say(link, state.typing)
    chatted(%{state | typing: nil})
  end

  defp typed(state, 13), do: chatted(%{state | typing: nil})
  defp typed(state, 27), do: chatted(%{state | typing: nil})
  defp typed(state, 8), do: chatted(%{state | typing: String.slice(state.typing, 0..-2//1)})
  defp typed(state, _code), do: state

  defp key_down(%{link: {_module, _link}} = state, code, key) do
    case Keys.input_key(code) do
      nil -> state
      name -> pressed(state, name, code, key)
    end
  end

  defp key_down(state, code, _key) do
    callback(state, :on_key, code)
    state
  end

  defp pressed(%{watching?: true} = state, name, _code, _key) when is_map_key(@pans, name) do
    {x, y} = Map.fetch!(@pans, name)
    {width, height} = :wxWindow.getClientSize(state.canvas)
    step = max(width, height) / 8
    panned(state, {x * step / max(width, 1), y * step / max(height, 1)})
    state
  end

  defp pressed(%{link: {module, link}} = state, name, code, key) do
    module.key(link, name, mods(key), true)
    %{state | down: Map.put(state.down, code, name)}
  end

  defp key_up(%{link: {module, link}} = state, code, key) do
    case Map.pop(state.down, code) do
      {nil, _down} ->
        state

      {name, down} ->
        module.key(link, name, mods(key), false)
        %{state | down: down}
    end
  end

  defp key_up(state, _code, _key), do: state

  defp let_go(%{link: {module, link}} = state) do
    for {_code, name} <- state.down, do: module.key(link, name, [], false)
    %{state | down: %{}}
  end

  defp let_go(state), do: %{state | down: %{}}

  defp moused(%{link: {module, link}} = state, event, point),
    do: module.mouse(link, Map.put(event, :at, fraction(state, point)))

  defp moused(_state, _event, _point), do: :ok

  defp panned(%{link: {module, link}}, fraction), do: module.pan(link, fraction)
  defp panned(_state, _fraction), do: :ok

  defp mods(wxKey(controlDown: ctrl, shiftDown: shift, altDown: alt, metaDown: meta)) do
    for {down?, mod} <- [{ctrl, :ctrl}, {shift, :shift}, {alt, :alt}, {meta, :meta}],
        down?,
        do: mod
  end

  defp fraction(state, {x, y}) do
    {width, height} = :wxWindow.getClientSize(state.canvas)
    {x / max(width, 1), y / max(height, 1)}
  end

  defp button(:left_down), do: :left
  defp button(:left_up), do: :left
  defp button(:right_down), do: :right
  defp button(:right_up), do: :right
  defp button(_middle), do: :middle

  defp lookup(table, key) do
    [{^key, value}] = :ets.lookup(table, key)
    value
  end

  defp paint_canvas(canvas, table, font) do
    :ets.update_counter(table, :counts, {3, 1})
    dc = :wxBufferedPaintDC.new(canvas)
    :wxDC.setBackground(dc, :wxBrush.new(lookup(table, :void)))
    :wxDC.clear(dc)

    case lookup(table, :bitmap) do
      nil ->
        draw_opening(dc, font, lookup(table, :opening), :wxWindow.getClientSize(canvas))

      {bitmap, at} ->
        :wxDC.drawBitmap(dc, bitmap, at)

      bitmap ->
        :wxDC.drawBitmap(dc, bitmap, {0, 0})
    end

    draw_stats(dc, font, lookup(table, :stats))
    :wxBufferedPaintDC.destroy(dc)
    :ok
  end

  defp draw_opening(_dc, _font, [], _size), do: :ok

  defp draw_opening(dc, font, rows, {width, height}) do
    :wxDC.setFont(dc, font)
    {_width, line} = :wxDC.getTextExtent(dc, "M")
    top = div(height - line * length(rows), 2)

    rows
    |> Enum.with_index()
    |> Enum.each(fn {row, index} ->
      runs = Hud.runs(row)
      {row_width, _height} = :wxDC.getTextExtent(dc, Hud.text(row))

      Enum.reduce(runs, div(width - row_width, 2), fn {text, _style} = run, x ->
        draw_run(
          dc,
          text,
          Hud.colour(run, &Cauldron2D.Palette.rgb/1) || {255, 255, 255},
          {x, top + index * line}
        )
      end)
    end)

    :ok
  end

  defp draw_stats(dc, font, text) when is_binary(text) do
    :wxDC.setFont(dc, font)
    :wxDC.setTextForeground(dc, {255, 255, 255})
    :wxDC.drawText(dc, text, {6, 4})
  end

  defp draw_stats(_dc, _font, _none), do: :ok

  defp paint_hud(hud, table, font, colours) do
    dc = :wxBufferedPaintDC.new(hud)
    :wxDC.setBackground(dc, :wxBrush.new(colours.background))
    :wxDC.clear(dc)
    :wxDC.setFont(dc, font)

    rows = table |> lookup(:status) |> hud_rows()
    rows |> Enum.with_index() |> Enum.each(&draw_row(dc, &1, colours.text))
    {messages, typing} = lookup(table, :chat)

    (Enum.map(messages, &[{&1.from <> " ", "#7fd6ff"}, {&1.text, nil}]) ++ typing_row(typing))
    |> Enum.with_index(length(rows) + 1)
    |> Enum.each(&draw_row(dc, &1, colours.text))

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

  defp typing_row(nil), do: []
  defp typing_row(text), do: [[{"say: ", "#ffd060"}, {text <> "_", nil}]]

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
