defmodule Cauldron2D.Robot do
  @moduledoc """
  A computer player: a process that joins a world as `{:robot, n}` and plays by its
  view, deciding every few frames through a brain module the game supplies.

      defmodule MyGame.Brain do
        @behaviour Cauldron2D.Robot

        def init(opts), do: %{}
        def decide(view, memory, %{tick: tick, skill: skill}), do: {%{held: MapSet.new([:thrust]), aim: nil}, memory}
        def gone?(view), do: view.me == nil
      end

      Cauldron2D.Robot.start_link(brain: MyGame.Brain, world: world, number: 1)

  `decide/3` is given the latest view, the brain's memory and `%{tick: n, skill: s}`, and
  returns the input to hold — a `t:Cauldron2D.Input.state/0`, or `nil` to leave the input
  as it is — with the memory to keep. The input is sent to the world only when it
  differs from what was last sent. `gone?/1` says the robot has no place in the world
  any more; it then leaves and stops. `init/1` is optional; without it the memory
  starts as `nil`, and `gone?/1` without it is never true.

  Every robot has a skill, drawn by `skill/0` between #{0.3} and 1.0 unless given: it
  sets how often the robot decides (`cadence/2`) and is passed to the brain for whatever
  else the game makes of it.

  ## Options

    * `:brain` — the module. Required
    * `:world` — the world to join. Required
    * `:number` — the robot's number; its id is `{:robot, number}`. Required
    * `:brain_opts` — given to the brain's `init/1`. Default `[]`
    * `:props` — merged over `%{username: "Robot n", robot?: true}` for the join.
      Default `%{}`
    * `:skill` — 0.3 to 1.0. Default `skill/0`
    * `:cadence` — `{fastest, slowest}`, frames between decisions at full and least
      skill. Default `{3, 9}`
  """

  use GenServer

  alias Cauldron2D.Player

  @least_skill 0.3

  @callback init(keyword()) :: term()
  @callback decide(view :: term(), memory :: term(), %{tick: pos_integer(), skill: float()}) ::
              {Cauldron2D.Input.state() | nil, term()}
  @callback gone?(view :: term()) :: boolean()

  @optional_callbacks init: 1, gone?: 1

  @doc "Start a robot; see the module documentation for the options. A refused join is `{:error, reason}`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "A skill drawn at random between #{@least_skill} and 1.0."
  @spec skill() :: float()
  def skill, do: @least_skill + (1.0 - @least_skill) * :rand.uniform()

  @doc "Every how many frames a robot of `skill` decides: `fastest` at full skill, `slowest` at the least."
  @spec cadence(float(), {pos_integer(), pos_integer()}) :: pos_integer()
  def cadence(skill, {fastest, slowest}),
    do: fastest + round((1.0 - skill) / (1.0 - @least_skill) * (slowest - fastest))

  @impl GenServer
  def init(opts) do
    brain = Keyword.fetch!(opts, :brain)
    world = Keyword.fetch!(opts, :world)
    number = Keyword.fetch!(opts, :number)
    id = {:robot, number}
    skill = Keyword.get_lazy(opts, :skill, &skill/0)

    props =
      Map.merge(%{username: "Robot #{number}", robot?: true}, Keyword.get(opts, :props, %{}))

    case Player.join(world, id, props) do
      :ok ->
        memory =
          if Code.ensure_loaded?(brain) and function_exported?(brain, :init, 1),
            do: brain.init(Keyword.get(opts, :brain_opts, [])),
            else: nil

        {:ok,
         %{
           brain: brain,
           world: world,
           id: id,
           skill: skill,
           cadence: cadence(skill, Keyword.get(opts, :cadence, {3, 9})),
           memory: memory,
           tick: 0,
           held: nil
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info({:cauldron_frame, %{view: view}}, state) do
    if Code.ensure_loaded?(state.brain) and function_exported?(state.brain, :gone?, 1) and
         state.brain.gone?(view) do
      Player.leave(state.world, state.id)
      {:stop, :normal, state}
    else
      {:noreply, state |> Map.update!(:tick, &(&1 + 1)) |> decide(view)}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp decide(state, view) do
    if rem(state.tick, state.cadence) == 0 do
      {input, memory} =
        state.brain.decide(view, state.memory, %{tick: state.tick, skill: state.skill})

      if input != nil and input != state.held, do: Player.input(state.world, state.id, input)
      %{state | memory: memory, held: input || state.held}
    else
      state
    end
  end
end
