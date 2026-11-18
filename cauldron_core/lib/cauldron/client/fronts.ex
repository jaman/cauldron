defmodule Cauldron.Client.Fronts do
  @moduledoc """
  The game's own screens (`Cauldron.Front`) in a client: which
  screens the game draws, the front showing, its clock, and its scene.

  The client keeps `:fronts` (the game's `fronts/1`) and `:front` (`nil`, or
  `%{screen, module, state, at}` for the front open) in its state.
  """

  alias Cauldron.Client.Game
  alias Cauldron.Front

  @frame_ms 33

  @doc "How often a front showing is ticked, in milliseconds."
  @spec frame_ms() :: pos_integer()
  def frame_ms, do: @frame_ms

  @doc "The game's fronts, given the client's mount props."
  @spec of(module(), map()) :: %{Front.screen() => module()}
  def of(game, props), do: Game.optional(game, :fronts, [props], %{})

  @doc "Whether the client's screen is one the game draws, and its front is open."
  @spec showing?(map()) :: boolean()
  def showing?(%{front: %{screen: screen}, screen: screen}), do: true
  def showing?(_state), do: false

  @doc """
  The client state with the front for its screen opened, given `context` (see
  `Cauldron.Front`); `{state, true}` when one was opened and its clock must start.
  A screen the game does not draw closes any front.
  """
  @spec open(map(), map(), integer()) :: {map(), boolean()}
  def open(%{screen: screen, fronts: fronts} = state, context, now) do
    case Map.fetch(fronts, screen) do
      {:ok, module} ->
        front = %{screen: screen, module: module, state: module.init(screen, context), at: now}
        {%{state | front: front}, state.front == nil}

      :error ->
        {%{state | front: nil}, false}
    end
  end

  @doc "The front moved on to `now`."
  @spec tick(map(), integer()) :: map()
  def tick(%{front: nil} = state, _now), do: state

  def tick(%{front: front} = state, now) do
    moved = Front.tick(front.module, front.state, max(0, now - front.at))
    %{state | front: %{front | state: moved, at: now}}
  end

  @doc "The front's reply to `event` with the player's `settings`, and the front holding its new state."
  @spec event(map(), term(), map()) :: {map(), Front.reply()}
  def event(%{front: front} = state, event, settings) do
    reply = front.module.event(front.state, event, settings)
    {%{state | front: %{front | state: reply.state}}, reply}
  end

  @doc "What the front draws."
  @spec scene(map()) :: Game.scene()
  def scene(%{front: front}), do: front.module.scene(front.state)

  @doc "The front's music, or `nil`."
  @spec cue(map()) :: Cauldron.Audio.Music.cue() | nil
  def cue(%{front: front}), do: Front.cue(front.module, front.state)
end
