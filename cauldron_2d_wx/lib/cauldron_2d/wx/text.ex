defmodule Cauldron2D.Wx.Text do
  @moduledoc """
  A wx panel that draws text items on a dark canvas and hands its keys to its owner —
  the screens a game puts around its worlds, drawn as a game draws them rather than
  built from widgets.

      text = Cauldron2D.Wx.Text.new(frame, owner: self(), backdrop: &MyGame.Wx.stars/3)
      Cauldron2D.Wx.Text.show(text, [{{:centre, 640}, 200, "DOTS", {127, 214, 255}, :title}, {60, 300, "Enter  play", {228, 231, 243}, :big}])

  An item is `{x, y, text, colour, size}` — `x` a left edge in pixels or `{:centre, x}`,
  `colour` an RGB triple, `size` one of `:small`, `:normal`, `:big`, `:title` — with an
  optional sixth element, an action: a click on the item's text sends the owner
  `{:cauldron_wx_text, :action, action}`. The owner also receives
  `{:cauldron_wx_text, :key, code}` for every key that goes down (wx key codes) and
  `{:cauldron_wx_text, :char, char}` for every character typed, and draws by calling
  `show/2` again.

  Options: `:owner` (default the caller); `:backdrop`, a function of the DC, the width
  and the height that draws behind the text, after the canvas is cleared to
  `:background` (default `{5, 6, 15}`); `:fonts` — points for `:small`, `:normal`,
  `:big`, `:title` (default 12, 15, 20, 48).
  """

  @behaviour :wx_object

  import Bitwise

  alias Cauldron2D.Wx.Const

  require Record

  Record.defrecordp(:wx, Record.extract(:wx, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxKey, Record.extract(:wxKey, from_lib: "wx/include/wx.hrl"))
  Record.defrecordp(:wxMouse, Record.extract(:wxMouse, from_lib: "wx/include/wx.hrl"))

  @background {5, 6, 15}

  @type item ::
          {integer() | {:centre, integer()}, integer(), String.t(), {byte(), byte(), byte()},
           :small | :normal | :big | :title}
          | tuple()

  @doc "The panel under `parent`."
  @spec new(term(), keyword()) :: term()
  def new(parent, opts \\ []),
    do: :wx_object.start_link(__MODULE__, {parent, Keyword.put_new(opts, :owner, self())}, [])

  @doc "Draw these items from now on."
  @spec show(term(), [item()]) :: :ok
  def show(text, items), do: :wx_object.cast(text, {:show, items})

  @doc "The panel's wx window."
  @spec window(term()) :: term()
  def window(text), do: :wx_object.call(text, :window)

  @doc "Give the panel the keyboard."
  @spec focus(term()) :: :ok
  def focus(text), do: :wx_object.cast(text, :focus)

  @doc "The canvas's size in pixels."
  @spec size(term()) :: {pos_integer(), pos_integer()}
  def size(text), do: :wx_object.call(text, :size)

  @impl :wx_object
  def init({parent, opts}) do
    panel = :wxPanel.new(parent, style: Const.wants_chars() ||| Const.full_repaint_on_resize())
    :wxWindow.setBackgroundStyle(panel, Const.bg_style_paint())
    scene = :ets.new(__MODULE__, [:set, :public])
    points = Keyword.get(opts, :fonts, small: 12, normal: 15, big: 20, title: 48)
    fonts = Map.new(points, fn {size, pts} -> {size, font(pts, size == :title)} end)
    backdrop = Keyword.get(opts, :backdrop)
    background = Keyword.get(opts, :background, @background)

    :wxPanel.connect(panel, :paint,
      callback: fn _event, _obj -> paint(panel, scene, fonts, background, backdrop) end
    )

    for event <- [:key_down, :char, :left_down], do: :wxPanel.connect(panel, event)
    {panel, %{panel: panel, scene: scene, owner: Keyword.fetch!(opts, :owner)}}
  end

  defp font(points, bold?),
    do:
      :wxFont.new(
        points,
        Const.teletype(),
        Const.normal(),
        if(bold?, do: Const.fontweight_bold(), else: Const.fontweight_normal())
      )

  @impl :wx_object
  def handle_call(:window, _from, state), do: {:reply, state.panel, state}
  def handle_call(:size, _from, state), do: {:reply, :wxWindow.getClientSize(state.panel), state}

  @impl :wx_object
  def handle_cast({:show, items}, state) do
    :ets.insert(state.scene, {:items, items})
    :wxWindow.refresh(state.panel, eraseBackground: false)
    {:noreply, state}
  end

  def handle_cast(:focus, state) do
    :wxWindow.setFocus(state.panel)
    {:noreply, state}
  end

  @impl :wx_object
  def handle_event(wx(event: wxKey(type: :key_down, keyCode: code)), state) do
    send(state.owner, {:cauldron_wx_text, :key, code})
    {:noreply, state}
  end

  def handle_event(wx(event: wxKey(type: :char, uniChar: char)), state) do
    send(state.owner, {:cauldron_wx_text, :char, char})
    {:noreply, state}
  end

  def handle_event(wx(event: wxMouse(type: :left_down, x: x, y: y)), state) do
    :wxWindow.setFocus(state.panel)

    case hit(state.scene, {x, y}) do
      {_rect, action} -> send(state.owner, {:cauldron_wx_text, :action, action})
      nil -> :ok
    end

    {:noreply, state}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp hit(scene, {x, y}) do
    case :ets.lookup(scene, :hits) do
      [{:hits, hits}] -> Enum.find(hits, fn {rect, _action} -> inside?(rect, {x, y}) end)
      [] -> nil
    end
  end

  defp inside?({left, top, width, height}, {x, y}),
    do: x >= left and x < left + width and y >= top and y < top + height

  @impl :wx_object
  def handle_info(_message, state), do: {:noreply, state}

  defp paint(panel, scene, fonts, background, backdrop) do
    items =
      case :ets.lookup(scene, :items) do
        [{:items, items}] -> items
        [] -> []
      end

    {width, height} = :wxWindow.getClientSize(panel)
    dc = :wxBufferedPaintDC.new(panel)
    :wxDC.setBackground(dc, :wxBrush.new(background))
    :wxDC.clear(dc)
    if backdrop, do: backdrop.(dc, width, height)

    hits =
      for item <- items,
          {x, y, text, colour, size} = Tuple.to_list(item) |> Enum.take(5) |> List.to_tuple(),
          text != "" do
        :wxDC.setFont(dc, Map.fetch!(fonts, size))
        :wxDC.setTextForeground(dc, colour)
        {w, h} = :wxDC.getTextExtent(dc, text)

        left =
          case x do
            {:centre, centre} -> centre - div(w, 2)
            left -> left
          end

        :wxDC.drawText(dc, text, {left, y})
        {{left, y, w, h}, action(item)}
      end

    :ets.insert(scene, {:hits, for({rect, action} <- hits, action != nil, do: {rect, action})})
    :wxBufferedPaintDC.destroy(dc)
    :ok
  end

  defp action(item) when tuple_size(item) >= 6, do: elem(item, 5)
  defp action(_item), do: nil
end
