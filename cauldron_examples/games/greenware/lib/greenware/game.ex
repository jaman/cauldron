defmodule Greenware.Game do
  @moduledoc """
  The world of Greenware: a hub, a scene, a mending, a conversation, a choice and an
  ending. It is one player's game and every callback is pure except the save, which is
  a deliberate exception for a single-player story.
  """

  @behaviour Cauldron.Game

  alias Cauldron.Presses
  alias Greenware.{Campaign, Layout, Mend, Progress}
  alias Greenware.Mend.Puzzles

  @default_options %{text_speed: :normal, guided: false, reduced_motion: false}

  @impl true
  def init(opts) do
    progress =
      if Keyword.get(opts, :fresh, false),
        do: Progress.new(),
        else: Progress.load()

    state = %{
      progress: progress,
      act: Map.get(progress, :act, 1),
      completed: Map.get(progress, :completed, []),
      seen: Map.get(progress, :seen, []),
      flags: Map.get(progress, :flags, %{}),
      ending_key: Map.get(progress, :ending),
      mode: :hub,
      hub: nil,
      scene: nil,
      scene_stage: :broken,
      mend: nil,
      dialogue: nil,
      choice: nil,
      ending: nil,
      finished: false,
      selected: 0,
      cursor: {0.5, 0.5},
      tool: :thumb,
      stroking: false,
      options: @default_options,
      player: %{held: MapSet.new(), aim: nil, request: nil, options: %{}},
      presses: Presses.new(),
      pointer_moved?: false,
      last_aim: nil,
      last_request: nil,
      handled_request: nil,
      time: 0.0,
      fade: 1.0,
      events: [],
      message: nil,
      message_until: 0.0
    }

    enter_hub(state, state.act, intro: true)
  end

  @impl true
  def join(state, _id, props) do
    options = Map.merge(@default_options, Map.get(props, :options, %{}))
    player = %{state.player | options: options}

    {:ok, %{state | player: player, options: options}}
  end

  @impl true
  def leave(state, _id) do
    save(state)
  end

  @impl true
  def handle_input(state, _id, input) do
    pointer = Map.get(input, :aim)
    moved? = pointer != nil and pointer != state.last_aim

    state =
      if moved? do
        %{state | cursor: pointer(pointer), last_aim: pointer, pointer_moved?: true}
      else
        state
      end

    options =
      case Map.get(input, :options) do
        nil -> state.options
        given -> Map.merge(@default_options, given)
      end

    player = %{
      state.player
      | held: Map.get(input, :held, MapSet.new()),
        aim: pointer,
        request: Map.get(input, :request)
    }

    %{state | player: player, options: options}
  end

  @impl true
  def step(state, dt) do
    held = state.player.held
    pressed = Presses.pressed(state.presses, held)

    state =
      state
      |> tick_clock(dt)
      |> tick_fade(dt)
      |> hover()
      |> move_cursor(held, dt)
      |> handle_request()
      |> handle_mode(pressed, held, dt)
      |> tick_dialogue(dt)
      |> tick_ending(dt)
      |> tick_mend(dt)
      |> tick_message(dt)

    %{state | presses: Presses.settle(state.presses, held, dt), pointer_moved?: false}
  end

  @impl true
  def view(state, _id) do
    screen = screen(state)

    %{
      me: %{},
      mode: state.mode,
      screen: screen,
      act: state.act,
      act_name: (Campaign.act(state.act) || %{name: "THE BAKE"}).name,
      time: state.time,
      cursor: state.cursor,
      selected: state.selected,
      tool: state.tool,
      options: state.options,
      guided: state.options.guided,
      fade: state.fade,
      finished: state.finished,
      message: if(state.message && state.time < state.message_until, do: state.message),
      hub: if(screen == :hub, do: hub_view(state)),
      scene: if(state.scene, do: scene_view(state)),
      mend: if(screen == :mend, do: mend_view(state)),
      dialogue: dialogue_view(state),
      choice: choice_view(state),
      ending: ending_view(state)
    }
  end

  @impl true
  def drain_events(state), do: {Enum.reverse(state.events), %{state | events: []}}

  def outcome(state) do
    if Map.get(state, :finished) do
      ending = Map.get(state, :ending) || %{title: "THE END", pages: []}

      %{
        title: ending.title,
        lines: Enum.map(ending.pages, fn {_speaker, text} -> text end),
        next: :title
      }
    end
  end

  # -- entering screens ----------------------------------------------------

  defp enter_hub(state, act, opts) do
    hub = Campaign.hub(act)

    state = %{
      state
      | act: act,
        hub: hub.id,
        mode: :hub,
        scene: nil,
        mend: nil,
        choice: nil,
        selected: 0,
        stroking: false,
        fade: 1.0
    }

    state = %{state | progress: Map.put(state.progress, :act, act)}
    state = save(state)
    state = select_first_open(state)
    seen_key = {:hub, act}

    cond do
      Keyword.get(opts, :intro, true) and seen_key not in state.seen ->
        state
        |> mark_seen(seen_key)
        |> start_dialogue(hub.intro, :hub_ready, :hub)

      true ->
        state
    end
  end

  defp select_first_open(state) do
    entries = hub_entries(state)
    index = Enum.find_index(entries, &(&1.available? and not &1.done? and &1.kind == :scene))
    index = index || Enum.find_index(entries, &(&1.kind == :exit and &1.available?))
    %{state | selected: index || 0}
  end

  defp enter_scene(state, id) do
    scene = Campaign.scene(id)

    state = %{
      state
      | scene: id,
        mode: :scene,
        scene_stage: if(id in state.completed, do: :used, else: :broken),
        hub: nil,
        mend: nil,
        choice: nil,
        stroking: false,
        selected: 0,
        fade: 1.0
    }

    state = %{state | cursor: center_of(scene.hotspot.rect)}
    seen_key = {:scene, id}

    if seen_key in state.seen do
      state
    else
      state
      |> mark_seen(seen_key)
      |> start_dialogue(scene.intro, :scene_ready, :scene)
    end
  end

  defp start_mend(state) do
    scene = Campaign.scene(state.scene)
    puzzle = Puzzles.puzzle(scene.puzzle)

    %{
      state
      | mode: :mend,
        mend: Mend.new(puzzle),
        tool: :thumb,
        stroking: false,
        cursor: {0.5, 0.55},
        fade: 1.0
    }
  end

  defp leave_mend(state), do: %{state | mode: :scene, mend: nil, stroking: false}

  defp fix_scene(state) do
    scene = Campaign.scene(state.scene)

    state
    |> Map.merge(%{
      mode: :scene,
      scene_stage: :fixed,
      mend: nil,
      stroking: false,
      fade: 1.0,
      cursor: center_of(scene.hotspot.rect)
    })
  end

  defp use_scene(state) do
    id = state.scene
    completed = Enum.uniq([id | state.completed])
    state = %{state | completed: completed, scene_stage: :used, mend: nil, stroking: false}
    state = %{state | progress: Map.put(state.progress, :completed, completed)}
    state = save(state)
    scene = Campaign.scene(id)
    state = emit(state, :mend)
    start_dialogue(state, scene.success, :after_scene, :scene)
  end

  defp start_choice(state) do
    options = [
      %{key: :fire, label: "FIRE", description: "Perfect. Still."},
      %{key: :green, label: "KEEP GREEN", description: "Alive. Changing."},
      %{key: :mend, label: "MEND THE SKY", description: "Become the Kiln."}
    ]

    %{state | mode: :choice, choice: %{title: "THE CHOICE", options: options, selected: 0}}
  end

  defp choose(state, key) do
    ending = Map.fetch!(Campaign.endings(), key)

    %{
      state
      | mode: :ending,
        choice: nil,
        ending: %{
          kind: key,
          title: ending.title,
          pages: ending.lines,
          index: 0,
          shown: 0.0,
          text: ""
        },
        progress: Map.put(state.progress, :ending, key)
    }
    |> save()
  end

  defp finish_ending(state) do
    %{state | finished: true, mode: :ending}
    |> save()
  end

  # -- input ---------------------------------------------------------------

  defp handle_request(%{player: %{request: nil}} = state), do: state

  defp handle_request(%{player: %{request: {number, request}}} = state) do
    if number == state.handled_request do
      state
    else
      state = %{state | handled_request: number}

      case request do
        :leave_mend -> leave_mend(state)
        :restart_scene -> enter_scene(state, state.scene)
        :save -> save(state)
        :hint -> hint(state)
        :leave -> state
        _ -> state
      end
    end
  end

  defp handle_request(state), do: state

  defp handle_mode(%{mode: :hub} = state, pressed, _held, _dt) do
    entries = hub_entries(state)

    cond do
      MapSet.member?(pressed, :interact) ->
        activate_hub(state, Enum.at(entries, state.selected))

      MapSet.member?(pressed, :left) or MapSet.member?(pressed, :up) ->
        %{state | selected: wrap_index(state.selected - 1, length(entries))}

      MapSet.member?(pressed, :right) or MapSet.member?(pressed, :down) ->
        %{state | selected: wrap_index(state.selected + 1, length(entries))}

      MapSet.member?(pressed, :hint) ->
        hint(state)

      true ->
        state
    end
  end

  defp handle_mode(%{mode: :scene} = state, pressed, _held, _dt) do
    cond do
      MapSet.member?(pressed, :interact) -> activate_scene(state)
      MapSet.member?(pressed, :hint) -> hint(state)
      MapSet.member?(pressed, :back) -> enter_hub(state, state.act, intro: false)
      true -> state
    end
  end

  defp handle_mode(%{mode: :mend} = state, pressed, held, dt) do
    state = handle_mend_pressed(state, pressed)

    state =
      if state.stroking and MapSet.member?(held, :interact),
        do: stroke(state, pressure(dt)),
        else: state

    state =
      if state.stroking and not MapSet.member?(held, :interact),
        do: %{state | stroking: false},
        else: state

    state
  end

  defp handle_mode(%{mode: :dialogue} = state, pressed, _held, _dt) do
    if MapSet.member?(pressed, :interact) or MapSet.member?(pressed, :back),
      do: advance_dialogue(state),
      else: state
  end

  defp handle_mode(%{mode: :choice} = state, pressed, _held, _dt) do
    count = length(state.choice.options)

    cond do
      MapSet.member?(pressed, :left) ->
        %{
          state
          | choice: %{state.choice | selected: wrap_index(state.choice.selected - 1, count)}
        }

      MapSet.member?(pressed, :right) ->
        %{
          state
          | choice: %{state.choice | selected: wrap_index(state.choice.selected + 1, count)}
        }

      MapSet.member?(pressed, :interact) ->
        option = Enum.at(state.choice.options, state.choice.selected)
        choose(state, option.key)

      true ->
        state
    end
  end

  defp handle_mode(%{mode: :ending} = state, pressed, _held, _dt) do
    if MapSet.member?(pressed, :interact) or MapSet.member?(pressed, :back),
      do: advance_ending(state),
      else: state
  end

  defp handle_mode(state, _pressed, _held, _dt), do: state

  defp activate_hub(state, nil), do: state

  defp activate_hub(state, %{available?: false}) do
    emit(state, :ui_refuse)
    |> message("The clay is not ready for this yet.")
  end

  defp activate_hub(state, %{kind: :exit}) do
    if Campaign.act_complete?(state.act, state.completed) do
      enter_hub(%{state | selected: 0}, state.act + 1, intro: true)
    else
      message(state, "Some things in this act are still unmended.")
    end
  end

  defp activate_hub(state, %{kind: :scene, id: id}) do
    if Campaign.available?(Campaign.scene(id), state.completed) do
      emit(enter_scene(state, id), :ui_choose)
    else
      emit(message(state, "Some earlier mend has not been made."), :ui_refuse)
    end
  end

  defp activate_scene(state) do
    scene = Campaign.scene(state.scene)
    hotspot = scene.hotspot
    pointer = Layout.cursor(%{cursor: state.cursor})
    cat_rect = {540, 248, 100, 100}

    cond do
      state.scene_stage == :fixed and Layout.in_rect?(pointer, hotspot.rect) ->
        emit(use_scene(state), :page)

      state.scene_stage == :used ->
        start_dialogue(state, scene.success, :scene_ready, :scene)

      Layout.in_rect?(pointer, hotspot.rect) ->
        emit(start_mend(state), :page)

      Layout.in_rect?(pointer, cat_rect) ->
        hint(state)

      true ->
        message(state, "The Cat looks at the broken thing. You should too.")
    end
  end

  defp handle_mend_pressed(%{mend: %{done?: true}} = state, pressed) do
    if MapSet.member?(pressed, :interact), do: fix_scene(state), else: state
  end

  defp handle_mend_pressed(state, pressed) do
    cursor = Layout.cursor(%{cursor: state.cursor})
    mend = state.mend

    cond do
      MapSet.member?(pressed, :back) -> leave_mend(state)
      MapSet.member?(pressed, :test) -> test_mend(state)
      MapSet.member?(pressed, :reset) -> %{state | mend: Mend.reset(mend), stroking: false}
      MapSet.member?(pressed, :undo) -> %{state | mend: Mend.undo(mend), stroking: false}
      tool_key(pressed) -> select_tool(state, tool_key(pressed))
      MapSet.member?(pressed, :interact) -> click_mend(state, cursor)
      true -> state
    end
  end

  defp click_mend(state, cursor) do
    {fx, fy, fw, fh} = Layout.field_rect()

    cond do
      Layout.in_rect?(cursor, Layout.test_button()) ->
        test_mend(state)

      Layout.in_rect?(cursor, Layout.reset_button()) ->
        %{state | mend: Mend.reset(state.mend), stroking: false}

      Layout.in_rect?(cursor, Layout.back_button()) ->
        leave_mend(state)

      tool = tool_at(cursor) ->
        select_tool(state, "tool_" <> Integer.to_string(tool + 1))

      Layout.in_rect?(cursor, {fx, fy, fw, fh}) ->
        state = %{state | mend: Mend.begin(state.mend), stroking: true}
        emit(stroke(state, 0.5), tool_event(state.tool))

      true ->
        state
    end
  end

  defp stroke(%{mend: nil} = state, _pressure), do: state

  defp stroke(state, pressure) do
    case Layout.field_cell(Layout.cursor(%{cursor: state.cursor})) do
      nil -> state
      {x, y} -> %{state | mend: Mend.apply(state.mend, state.tool, x, y, pressure)}
    end
  end

  defp test_mend(state) do
    mend = state.mend |> Mend.check() |> Mend.finish()
    state = %{state | mend: mend}
    if mend.result.ok?, do: emit(state, :mend), else: emit(state, :fail)
  end

  defp tool_at(cursor) do
    Enum.find(0..6, fn index -> Layout.in_rect?(cursor, Layout.tool_rect(index)) end)
  end

  defp press_tool(state, tool) do
    if tool in Mend.tools(), do: %{state | tool: tool}, else: state
  end

  defp select_tool(state, key) do
    index = String.to_integer(String.replace(key, "tool_", "")) - 1
    tool = Enum.at(Mend.tools(), index)
    emit(press_tool(state, tool), :ui_move)
  end

  defp tool_key(pressed) do
    Enum.find_value(1..7, fn number ->
      action = String.to_atom("tool_#{number}")
      if MapSet.member?(pressed, action), do: Atom.to_string(action)
    end)
  end

  defp tool_event(:wire), do: :wire
  defp tool_event(:water), do: :water
  defp tool_event(:heat), do: :heat
  defp tool_event(_), do: :clay

  defp pressure(dt), do: min(0.45, max(0.08, dt * 5.0))

  # -- dialogue ------------------------------------------------------------

  defp start_dialogue(state, pages, after_action, under) do
    pages = Enum.reject(pages || [], fn {_speaker, text} -> text in [nil, ""] end)

    if pages == [] do
      finish_dialogue(%{state | mode: under, dialogue: %{after: after_action, under: under}})
    else
      %{
        state
        | mode: :dialogue,
          dialogue: %{pages: pages, index: 0, shown: 0.0, after: after_action, under: under}
      }
    end
  end

  defp advance_dialogue(%{dialogue: nil} = state), do: state

  defp advance_dialogue(state) do
    dialogue = state.dialogue
    {_speaker, text} = Enum.at(dialogue.pages, dialogue.index)
    length = String.length(text)

    cond do
      dialogue.shown < length ->
        put_in(state, [:dialogue, :shown], length * 1.0)

      dialogue.index + 1 < length(dialogue.pages) ->
        put_in(state, [:dialogue, :index], dialogue.index + 1)
        |> put_in([:dialogue, :shown], 0.0)

      true ->
        finish_dialogue(state)
    end
  end

  defp finish_dialogue(state) do
    action = state.dialogue.after
    under = state.dialogue.under
    state = %{state | dialogue: nil, mode: under}

    case action do
      :hub_ready -> %{state | mode: :hub}
      :scene_ready -> %{state | mode: :scene}
      :after_scene -> after_scene(state)
      :choice -> start_choice(state)
      :ending -> finish_ending(state)
      _ -> %{state | mode: :hub}
    end
  end

  defp tick_dialogue(%{mode: :dialogue, dialogue: dialogue} = state, dt) do
    {_speaker, text} = Enum.at(dialogue.pages, dialogue.index)
    speed = speed(state.options.text_speed)
    shown = min(String.length(text) * 1.0, dialogue.shown + speed * dt)
    put_in(state, [:dialogue, :shown], shown)
  end

  defp tick_dialogue(state, _dt), do: state

  defp tick_ending(%{mode: :ending, ending: ending} = state, dt) do
    {_speaker, text} = Enum.at(ending.pages, ending.index)
    speed = speed(state.options.text_speed)
    shown = min(String.length(text) * 1.0, ending.shown + speed * dt)
    put_in(state, [:ending, :shown], shown)
  end

  defp tick_ending(state, _dt), do: state

  defp advance_ending(state) do
    ending = state.ending
    {_speaker, text} = Enum.at(ending.pages, ending.index)
    length = String.length(text)

    cond do
      ending.shown < length ->
        put_in(state, [:ending, :shown], length * 1.0)

      ending.index + 1 < length(ending.pages) ->
        put_in(state, [:ending, :index], ending.index + 1)
        |> put_in([:ending, :shown], 0.0)

      true ->
        finish_ending(state)
    end
  end

  defp speed(:slow), do: 24.0
  defp speed(:fast), do: 90.0
  defp speed(_), do: 46.0

  # -- progression ---------------------------------------------------------

  defp after_scene(state) do
    if state.scene == :sky do
      start_choice(state)
    else
      enter_hub(state, state.act, intro: false)
    end
  end

  defp hint(state) do
    text =
      cond do
        state.scene -> hint_for(Campaign.scene(state.scene))
        state.mend -> state.mend.puzzle.hint
        true -> "The Cat is asleep. The workshop is quiet."
      end

    start_dialogue(
      state,
      [{:cat, text}],
      if(state.scene, do: :scene_ready, else: :hub_ready),
      if(state.scene, do: :scene, else: :hub)
    )
  end

  defp hint_for(scene) do
    puzzle = Puzzles.puzzle(scene.puzzle)
    puzzle.hint
  end

  defp mark_seen(state, key) do
    seen = Enum.uniq([key | state.seen])
    %{state | seen: seen, progress: Map.put(state.progress, :seen, seen)}
  end

  defp save(state) do
    progress = %{
      state.progress
      | act: state.act,
        completed: state.completed,
        seen: state.seen,
        flags: state.flags,
        ending: state.progress.ending
    }

    Progress.save(progress)
    %{state | progress: progress}
  end

  # -- timing --------------------------------------------------------------

  defp tick_clock(state, dt), do: %{state | time: state.time + dt}

  defp tick_fade(%{fade: fade} = state, dt) when fade > 0.0,
    do: %{state | fade: max(0.0, fade - dt * 2.4)}

  defp tick_fade(state, _dt), do: state

  defp tick_mend(%{mend: nil} = state, _dt), do: state
  defp tick_mend(state, dt), do: %{state | mend: Mend.step(state.mend, dt)}

  defp tick_message(state, _dt) do
    if state.message && state.time >= state.message_until,
      do: %{state | message: nil},
      else: state
  end

  defp message(state, text) do
    %{state | message: text, message_until: state.time + 3.0}
  end

  defp emit(state, event), do: %{state | events: [event | state.events]}

  # -- cursor and hover ----------------------------------------------------

  defp pointer({x, y}) when x >= 0.0 and x <= 1.02 and y >= 0.0 and y <= 1.02,
    do: {x |> max(0.0) |> min(1.0), y |> max(0.0) |> min(1.0)}

  defp pointer({x, y}) do
    {x |> Kernel./(80) |> max(0.0) |> min(1.0), y |> Kernel./(45) |> max(0.0) |> min(1.0)}
  end

  defp hover(%{pointer_moved?: true, mode: :hub} = state) do
    cursor = Layout.cursor(%{cursor: state.cursor})
    entries = hub_entries(state)

    case Enum.find_index(entries, fn entry -> Layout.in_rect?(cursor, entry.rect) end) do
      nil -> state
      index -> %{state | selected: index}
    end
  end

  defp hover(%{pointer_moved?: true, mode: :choice} = state) do
    cursor = Layout.cursor(%{cursor: state.cursor})

    case Enum.find_index(0..(length(state.choice.options) - 1), fn index ->
           Layout.in_rect?(cursor, Layout.choice_rect(index))
         end) do
      nil -> state
      index -> %{state | choice: %{state.choice | selected: index}}
    end
  end

  defp hover(state), do: state

  defp move_cursor(%{mode: mode} = state, held, dt) when mode in [:scene, :mend] do
    speed = if mode == :mend, do: 0.62, else: 0.5
    dx = bool(MapSet.member?(held, :right)) - bool(MapSet.member?(held, :left))
    dy = bool(MapSet.member?(held, :down)) - bool(MapSet.member?(held, :up))

    if dx == 0 and dy == 0 do
      state
    else
      {x, y} = state.cursor
      %{state | cursor: {clamp01(x + dx * speed * dt), clamp01(y + dy * speed * dt)}}
    end
  end

  defp move_cursor(state, _held, _dt), do: state

  defp bool(true), do: 1
  defp bool(false), do: 0
  defp clamp01(value), do: value |> max(0.0) |> min(1.0)
  defp wrap_index(_index, 0), do: 0
  defp wrap_index(index, count), do: Integer.mod(index, count)
  defp center_of({x, y, width, height}), do: {(x + width / 2) / 640, (y + height / 2) / 360}

  # -- views ---------------------------------------------------------------

  defp screen(%{mode: :mend}), do: :mend
  defp screen(%{mode: :ending}), do: :ending
  defp screen(%{scene: scene}) when not is_nil(scene), do: :scene
  defp screen(_), do: :hub

  defp hub_view(state) do
    hub = Campaign.hub(state.act)
    entries = hub_entries(state)

    %{
      id: hub.id,
      act: state.act,
      title: hub.title,
      subtitle: hub.subtitle,
      bg: hub.bg,
      entries: entries
    }
  end

  defp hub_entries(state) do
    hub = Campaign.hub(state.act)
    scenes = Campaign.act_scenes(state.act)

    entries =
      Enum.map(scenes, fn scene ->
        %{
          kind: :scene,
          id: scene.id,
          icon: scene.puzzle,
          label: Campaign.hub_label(scene.id),
          available?: Campaign.available?(scene, state.completed),
          done?: scene.id in state.completed,
          optional?: scene.optional?
        }
      end)

    entries =
      if Campaign.act_complete?(state.act, state.completed) and hub.exit do
        entries ++
          [
            %{
              kind: :exit,
              id: hub.exit.to,
              icon: :door,
              label: hub.exit.label,
              available?: true,
              done?: false,
              optional?: false
            }
          ]
      else
        entries
      end

    slots = Layout.hub_slots(length(entries))
    Enum.zip_with(entries, slots, fn entry, rect -> Map.put(entry, :rect, rect) end)
  end

  defp scene_hotspot(scene, :fixed),
    do: %{scene.hotspot | label: scene.use.label, kind: :use}

  defp scene_hotspot(scene, _stage), do: scene.hotspot

  defp scene_view(state) do
    scene = Campaign.scene(state.scene)
    {kind, x, y} = Map.get(scene, :prop) || {scene.puzzle, 340, 230}

    %{
      id: scene.id,
      act: state.act,
      title: scene.title,
      subtitle: scene.subtitle,
      bg: scene.bg,
      objective: scene.objective,
      stage: state.scene_stage,
      use: scene.use,
      hotspot: scene_hotspot(scene, state.scene_stage),
      completed?: scene.id in state.completed,
      figures: scene.figures,
      prop: {kind, x, y}
    }
  end

  defp mend_view(state) do
    mend = state.mend

    %{
      puzzle: Map.take(mend.puzzle, [:id, :title, :goal, :hint, :colour, :holes, :mask, :zones]),
      heights: mend.heights,
      wire: mend.wire,
      wet: mend.wet,
      fired: mend.fired,
      clay: mend.clay,
      water: mend.water,
      fuel: mend.fuel,
      rev: mend.rev,
      result: mend.result,
      done?: mend.done?,
      tool: state.tool
    }
  end

  defp dialogue_view(%{dialogue: nil}), do: nil

  defp dialogue_view(%{dialogue: dialogue}) do
    {speaker, text} = Enum.at(dialogue.pages, dialogue.index)
    visible = String.slice(text, 0, floor(dialogue.shown))

    %{
      speaker: speaker,
      text: visible,
      page: dialogue.index + 1,
      total: length(dialogue.pages),
      prompt?: dialogue.shown >= String.length(text)
    }
  end

  defp choice_view(%{choice: nil}), do: nil
  defp choice_view(%{choice: choice}), do: choice

  defp ending_view(%{mode: :ending, ending: ending}) do
    {speaker, text} = Enum.at(ending.pages, ending.index)

    %{
      kind: ending.kind,
      title: ending.title,
      pages: ending.pages,
      index: ending.index,
      text: String.slice(text, 0, floor(ending.shown)),
      speaker: speaker,
      prompt?: ending.shown >= String.length(text)
    }
  end

  defp ending_view(_), do: nil
end
