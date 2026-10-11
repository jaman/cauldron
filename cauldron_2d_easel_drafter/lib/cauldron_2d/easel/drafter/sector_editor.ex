defmodule Cauldron2D.Easel.Drafter.SectorEditor do
  @moduledoc """
  The sector map editor in the terminal: rooms drawn on a plan from above, a
  first-person view of them beside it, and the room in hand's heights, pictures and
  light set from the keys.

      Drafter.run(Cauldron2D.Easel.Drafter.SectorEditor, props: %{path: "priv/maps/hall.json"})
      mix cauldron.sectors priv/maps/hall.json

  The plan is `Cauldron2D.Easel.Drafter.Plan`; the view is drawn by
  `Cauldron2D.Sectors.View` with `Cauldron2D.Easel.SectorArt`'s pictures, or a game's
  own given as `:art`.

  ## Keys

  `m` switches between drawing and choosing. Drawing: a press on the plan adds a
  corner, `Enter` closes the room, `Backspace` takes back a corner, `Esc` drops the room.
  Choosing: a press picks the room under it and stands the eye there. With a room in
  hand: `f`/`F` floor down or up, `c`/`C` ceiling down or up, `[`/`]` light, `t` the
  floor's picture, `T` the ceiling's, `w` its walls', `x` removes it. The eye: `i`/`k`
  forward and back, `j`/`l` turn. The plan: arrows pan, `+`/`-` zoom. `u` undoes, `U`
  redoes, `s` saves, `^Q` quits.

  ## Mount props

    * `:path` — the document file, read if it exists and written by `s`. Required
    * `:grid` — the snap for a new document. Default `32`
    * `:art` — `%{palette:, pictures:, names:}` as `Cauldron2D.Easel.SectorArt.get/0`
      gives it. Default that
  """

  use Drafter.App

  alias Cauldron2D.Easel.Drafter.Plan
  alias Cauldron2D.Easel.{SectorArt, Sectors}
  alias Cauldron2D.Sectors.{Frame, Pictures, View}
  alias Cauldron2D.Sectors.Map, as: SectorMap

  @atlas :sector_editor
  @height_step 8
  @light_step 16
  @eye_height 41
  @walk 16.0
  @turn :math.pi() / 16
  @pan 0.25

  @doc "Make the editor's widgets known to drafter; `mount/1` does this."
  @spec register_widgets() :: :ok
  def register_widgets do
    for widget <- [Plan, Cauldron2D.Drafter.Surface] do
      Code.ensure_loaded!(widget)
      Drafter.Widget.Registry.register(widget)
    end

    unless Cauldron2D.Atlas.installed?(@atlas) do
      @atlas |> Cauldron2D.Atlas.new(tile: 16, void: {0, 0, 0}) |> Cauldron2D.Atlas.install()
    end

    :ok
  end

  @impl true
  def mount(props) do
    register_widgets()
    path = Map.fetch!(props, :path)

    doc =
      case Sectors.load(path) do
        {:ok, doc} -> doc
        {:error, _missing} -> Sectors.new(grid: Map.get(props, :grid, 32))
      end

    rebuilt(%{
      doc: doc,
      path: path,
      art: Map.get(props, :art) || SectorArt.get(),
      map: nil,
      mode: :draw,
      drafting: [],
      selected: nil,
      eye: %{x: 128.0, y: 128.0, angle: :math.pi() / 2},
      view: %{center: {128.0, 128.0}, scale: 0.25},
      status: "m chooses rooms   a press adds a corner   Enter closes a room"
    })
  end

  @impl true
  def refresh_rate, do: "30fps"

  @impl true
  def render(state) do
    me = self()

    vertical([
      horizontal(
        [
          {:sector_plan,
           [
             id: :plan,
             doc: state.doc,
             view: state.view,
             drafting: state.drafting,
             selected: state.selected,
             eye: state.eye,
             on_point: :point,
             flex: 3
           ]},
          vertical(
            [
              {:cauldron_surface,
               [
                 id: :preview,
                 atlas: @atlas,
                 picture: fn size, aspect -> preview(state, size, aspect) end,
                 flex: 1
               ]},
              label(room_line(state)),
              label(mode_line(state), style: %{fg: :bright_black})
            ],
            flex: 2
          )
        ],
        flex: 1,
        gap: 1
      ),
      horizontal(
        [
          compact_button("draw/choose m", on_click: fn -> send(me, {:sectors, :mode}) end),
          compact_button("undo u", on_click: fn -> send(me, {:sectors, :undo}) end),
          compact_button("save s", on_click: fn -> send(me, {:sectors, :save}) end)
        ],
        gap: 1
      ),
      label(state.status, style: %{fg: :yellow})
    ])
  end

  defp compact_button(text, opts), do: button(text, Keyword.put(opts, :compact, true))

  defp room_line(%{selected: nil}), do: "no room in hand"

  defp room_line(%{selected: id, doc: doc}) do
    case Map.get(doc.sectors, id) do
      nil ->
        "no room in hand"

      room ->
        "room #{id}  floor #{trunc(room.floor)} #{room.floor_picture}  ceiling #{trunc(room.ceiling)} #{room.ceiling_picture}  light #{room.light}"
    end
  end

  defp mode_line(state),
    do:
      "#{state.mode}  ·  #{map_size(state.doc.sectors)} rooms  ·  #{length(state.drafting)} corners  ·  #{state.path}"

  defp preview(%{map: nil}, {width, height}, _aspect), do: black(width, height)

  defp preview(state, {width, height}, aspect) do
    case SectorMap.sector_at(state.map, {state.eye.x, state.eye.y}) do
      nil ->
        black(width, height)

      sector ->
        floor = elem(state.map.sectors, sector).floor

        eye = %{
          x: state.eye.x,
          y: state.eye.y,
          z: floor + @eye_height,
          angle: state.eye.angle,
          sectors: state.map.sectors,
          sides: state.map.sides
        }

        %{frame: frame} =
          View.render(
            Frame.new(max(width, 8), max(height, 8)),
            state.art.pictures,
            state.map,
            eye,
            stretch: 1.2 * aspect,
            contrast: 16
          )

        Frame.to_raster(frame, state.art.palette)
    end
  end

  defp black(width, height),
    do:
      FrenchCurve.Raster.from_rgba(
        max(width, 1),
        max(height, 1),
        :binary.copy(<<0, 0, 0, 255>>, max(width, 1) * max(height, 1))
      )

  defp rebuilt(state) do
    map =
      case Sectors.to_map(state.doc, &Pictures.id(state.art.pictures, &1)) do
        {:ok, map} -> map
        {:error, :empty} -> nil
      end

    %{state | map: map}
  end

  defp changed(state, doc), do: rebuilt(%{state | doc: doc})

  @impl true
  def handle_event(:point, %{x: x, y: y}, %{mode: :draw} = state),
    do:
      {:ok,
       %{
         state
         | drafting: state.drafting ++ [{x, y}],
           status: "#{length(state.drafting) + 1} corners   Enter closes"
       }}

  def handle_event(:point, %{x: x, y: y}, state) do
    case Sectors.sector_at(state.doc, {x, y}) do
      nil ->
        {:ok, %{state | selected: nil, status: "nothing there"}}

      id ->
        {:ok,
         %{
           state
           | selected: id,
             eye: %{state.eye | x: x * 1.0, y: y * 1.0},
             status: "room #{id} in hand"
         }}
    end
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  @impl true
  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event({:key, key}, state), do: {:ok, key(key, state)}
  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def on_message({:sectors, :mode}, state), do: key(:m, state)
  def on_message({:sectors, :undo}, state), do: key(:u, state)
  def on_message({:sectors, :save}, state), do: key(:s, state)
  def on_message(_message, state), do: state

  defp key(:m, state) do
    mode = if state.mode == :draw, do: :choose, else: :draw
    %{state | mode: mode, drafting: [], status: "#{mode}"}
  end

  defp key(:enter, %{drafting: points} = state) when length(points) >= 3 do
    doc = Sectors.draw_room(state.doc, points)

    if doc == state.doc,
      do: %{state | drafting: [], status: "that room overlaps another or has no area"},
      else: %{changed(state, doc) | drafting: [], status: "room drawn"}
  end

  defp key(:backspace, state), do: %{state | drafting: Enum.drop(state.drafting, -1)}
  defp key(:escape, state), do: %{state | drafting: [], status: "dropped"}
  defp key(:u, state), do: %{changed(state, Sectors.undo(state.doc)) | status: "undone"}
  defp key(:U, state), do: %{changed(state, Sectors.redo(state.doc)) | status: "redone"}

  defp key(:s, state) do
    case Sectors.save(state.doc, state.path) do
      :ok -> %{state | status: "saved #{state.path}"}
      {:error, reason} -> %{state | status: "could not save: #{inspect(reason)}"}
    end
  end

  defp key(:i, state), do: walk(state, @walk)
  defp key(:k, state), do: walk(state, -@walk)
  defp key(:j, state), do: %{state | eye: %{state.eye | angle: state.eye.angle + @turn}}
  defp key(:l, state), do: %{state | eye: %{state.eye | angle: state.eye.angle - @turn}}
  defp key(:up, state), do: pan(state, {0, 1})
  defp key(:down, state), do: pan(state, {0, -1})
  defp key(:left, state), do: pan(state, {-1, 0})
  defp key(:right, state), do: pan(state, {1, 0})
  defp key(:+, state), do: zoom(state, 2.0)
  defp key(:=, state), do: zoom(state, 2.0)
  defp key(:-, state), do: zoom(state, 0.5)
  defp key(key, %{selected: id} = state) when id != nil, do: room_key(key, id, state)
  defp key(_key, state), do: state

  defp room_key(:f, id, state), do: adjust(state, id, :floor, -@height_step)
  defp room_key(:F, id, state), do: adjust(state, id, :floor, @height_step)
  defp room_key(:c, id, state), do: adjust(state, id, :ceiling, -@height_step)
  defp room_key(:C, id, state), do: adjust(state, id, :ceiling, @height_step)
  defp room_key(:"[", id, state), do: adjust(state, id, :light, -@light_step)
  defp room_key(:"]", id, state), do: adjust(state, id, :light, @light_step)
  defp room_key(:t, id, state), do: next_picture(state, id, :floor_picture)
  defp room_key(:T, id, state), do: next_picture(state, id, :ceiling_picture)
  defp room_key(:w, id, state), do: next_walls(state, id)

  defp room_key(:x, id, state),
    do: %{
      changed(state, Sectors.delete_sector(state.doc, id))
      | selected: nil,
        status: "room #{id} removed"
    }

  defp room_key(_key, _id, state), do: state

  defp adjust(state, id, field, step) do
    room = Map.fetch!(state.doc.sectors, id)
    value = Map.fetch!(room, field) + step
    value = if field == :light, do: value |> max(0) |> min(255), else: value
    changed(state, Sectors.set_sector(state.doc, id, %{field => value}))
  end

  defp next_picture(state, id, field) do
    room = Map.fetch!(state.doc.sectors, id)

    changed(
      state,
      Sectors.set_sector(state.doc, id, %{
        field => following(state.art.names, Map.fetch!(room, field))
      })
    )
  end

  defp next_walls(state, id) do
    doc =
      state.doc.lines
      |> Enum.filter(fn {_line_id, line} -> line.front.sector == id and line.back == nil end)
      |> Enum.reduce(state.doc, fn {line_id, line}, acc ->
        Sectors.set_side(acc, line_id, :front, %{
          middle: following(state.art.names, line.front.middle)
        })
      end)

    changed(state, doc)
  end

  defp following(names, current) do
    index = Enum.find_index(names, &(&1 == current)) || -1
    Enum.at(names, rem(index + 1, length(names)))
  end

  defp walk(state, distance) do
    eye = state.eye

    %{
      state
      | eye: %{
          eye
          | x: eye.x + distance * :math.cos(eye.angle),
            y: eye.y + distance * :math.sin(eye.angle)
        }
    }
  end

  defp pan(state, {dx, dy}) do
    {cx, cy} = state.view.center
    step = @pan * 200 / state.view.scale
    %{state | view: %{state.view | center: {cx + dx * step, cy + dy * step}}}
  end

  defp zoom(state, factor),
    do: %{
      state
      | view: %{state.view | scale: (state.view.scale * factor) |> max(0.02) |> min(8.0)}
    }
end
