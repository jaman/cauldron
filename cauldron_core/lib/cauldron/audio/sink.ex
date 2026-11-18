defmodule Cauldron.Audio.Sink do
  @moduledoc """
  Where sound goes once it is mixed: the `:sink` option of `Cauldron.Audio.start_link/1`,
  and of the sessions, links and front ends that start one.

      Cauldron.Audio.start_link(name: nil, sink: Cauldron.Audio.Sink.silent())
      Cauldron.Net.Link.Local.start_link(game: MyGame.Client, sink: Cauldron.Audio.Sink.speaker(), ...)
  """

  @type t :: module() | {module(), keyword()}

  @doc "This machine's speaker."
  @spec speaker() :: t()
  def speaker, do: {TuningFork.Sink.Speaker, []}

  @doc "Nowhere: the sound is mixed and dropped, as in tests."
  @spec silent() :: t()
  def silent, do: TuningFork.Sink.Silent

  @doc """
  Messages to `owner`, paced to real time: each chunk of signed 16-bit little-endian PCM
  arrives as `{:pcm, chunk}`. `opts` may set `:lead_ms`, how much sound is kept in flight.
  """
  @spec process(pid(), keyword()) :: t()
  def process(owner, opts \\ []), do: {TuningFork.Sink.Process, [owner: owner] ++ opts}

  @doc "A PulseAudio or PipeWire server, such as `\"tcp:127.0.0.1:4713\"`, through `pacat`."
  @spec pulse(String.t()) :: t()
  def pulse(server), do: {TuningFork.Sink.Pulse, server: server}
end
