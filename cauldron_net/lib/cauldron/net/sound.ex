defmodule Cauldron.Net.Sound do
  @moduledoc """
  Plays the PCM a `Cauldron.Net.Link.Socket` delivers through this machine's speaker,
  in a process of its own so the writes never hold up whoever draws.

      {:ok, sound} = Cauldron.Net.Sound.start_link()
      Cauldron.Net.Sound.play(sound, chunk)

  Options: `:sink`, a `Cauldron.Audio.Sink` (default `Cauldron.Audio.Sink.speaker/0`);
  `:rate` and `:channels` (default 44100 and 2). The sink opens on the first chunk;
  `format/3` sets the rate and channels the next chunks come in, reopening it.
  """

  use GenServer

  alias Cauldron.Audio.Sink

  @doc "Start the player."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @doc "Queue a chunk of signed 16-bit little-endian PCM."
  @spec play(GenServer.server(), binary()) :: :ok
  def play(sound, chunk), do: GenServer.cast(sound, {:play, chunk})

  @doc "The rate and channels the chunks come in from now on."
  @spec format(GenServer.server(), pos_integer(), 1 | 2) :: :ok
  def format(sound, rate, channels), do: GenServer.cast(sound, {:format, rate, channels})

  @impl GenServer
  def init(opts) do
    {sink, sink_opts} = split(Keyword.get(opts, :sink, Sink.speaker()))

    {:ok,
     %{
       sink: sink,
       sink_opts: sink_opts,
       opts: Keyword.take(opts, [:rate, :channels]),
       device: nil
     }}
  end

  @impl GenServer
  def handle_cast({:format, rate, channels}, state) do
    if state.device, do: state.sink.close(state.device)
    {:noreply, %{state | device: nil, opts: [rate: rate, channels: channels]}}
  end

  def handle_cast({:play, chunk}, %{device: nil} = state) do
    defaults = Keyword.merge([rate: 44_100, channels: 2, lead: 1_024], state.sink_opts)

    case state.sink.open(Keyword.merge(defaults, state.opts)) do
      {:ok, device} -> handle_cast({:play, chunk}, %{state | device: device})
      {:error, _reason} -> {:noreply, state}
    end
  end

  def handle_cast({:play, chunk}, state) do
    state.sink.write(state.device, chunk)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{device: nil}), do: :ok
  def terminate(_reason, %{sink: sink, device: device}), do: sink.close(device)

  defp split({sink, sink_opts}), do: {sink, sink_opts}
  defp split(sink), do: {sink, []}
end
