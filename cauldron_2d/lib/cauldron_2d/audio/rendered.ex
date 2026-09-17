defmodule Cauldron2D.Audio.Rendered do
  @moduledoc """
  Every sound a game plays, rendered once: a `TuningFork.Voice` at a rate becomes mono
  PCM the first time it is asked for and is kept in an ETS table for every stage on the
  node after, whatever its gain or pan, which are applied to the copy each time.

      pcm = Cauldron2D.Audio.Rendered.fetch(voice, 44_100)

  Voices are deterministic, so a rendering is the sound; a stage replays it in place of
  synthesising it again.
  """

  use GenServer

  alias TuningFork.Voice

  @table __MODULE__

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The mono rendering of `voice` at `rate`, at unit gain and centred, rendered now if it was not before."
  @spec fetch(Voice.t(), pos_integer()) :: binary()
  def fetch(%Voice{} = voice, rate) do
    plain = %{voice | gain: 1.0, pan: 0.0}
    key = {plain, rate}

    case :ets.lookup(@table, key) do
      [{^key, pcm}] ->
        pcm

      [] ->
        pcm = Voice.render(plain, rate)
        :ets.insert(@table, {key, pcm})
        pcm
    end
  end

  @doc "How many renderings are kept."
  @spec count() :: non_neg_integer()
  def count, do: :ets.info(@table, :size)

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end
end
