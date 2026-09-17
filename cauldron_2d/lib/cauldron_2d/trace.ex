defmodule Cauldron2D.Trace do
  @moduledoc """
  A trace of what happened and when, written as one line per event, and read back for
  `mix cauldron.report`.

      Cauldron2D.Trace.start()
      Cauldron2D.Trace.write(:mouse, x: 37, tile: 13.25)
      Cauldron2D.Trace.stop()

  `start/0` opens the file `CAULDRON_TRACE` names — `1` for `cauldron_trace.log` in the
  current directory — and does nothing when it is unset; every `write/2` is then a
  no-op. A line is `t=<ms since start> kind=<kind> key=value ...`; floats are written
  to two places.

  `read!/1`, `at/1`, `summary/1` and `latency/3` are what a report is made from.
  """

  @key {__MODULE__, :device}
  @origin {__MODULE__, :origin}

  @type event :: %{String.t() => String.t()}

  @doc "Open the trace and write a `start` event, if `CAULDRON_TRACE` is set. Returns whether tracing is on."
  @spec start() :: boolean()
  def start do
    case path() do
      nil ->
        false

      path ->
        device = File.open!(path, [:write, :delayed_write, :utf8])
        :persistent_term.put(@key, device)
        :persistent_term.put(@origin, System.monotonic_time(:microsecond))
        write(:start, path: path)
        true
    end
  end

  @doc "Whether a trace is open."
  @spec on?() :: boolean()
  def on?, do: :persistent_term.get(@key, nil) != nil

  @doc "Append one event: `kind` names it, `fields` become `key=value` pairs. A no-op when no trace is open."
  @spec write(atom(), keyword()) :: :ok
  def write(kind, fields \\ []) do
    case :persistent_term.get(@key, nil) do
      nil ->
        :ok

      device ->
        elapsed = (System.monotonic_time(:microsecond) - :persistent_term.get(@origin)) / 1000
        line = Enum.map_join(fields, " ", fn {key, value} -> "#{key}=#{format(value)}" end)

        IO.write(
          device,
          String.trim_trailing("t=#{Float.round(elapsed, 1)} kind=#{kind} #{line}") <> "\n"
        )
    end
  catch
    :error, :terminated -> forget()
  end

  @doc "Write a `stop` event, flush and close. A no-op when no trace is open, or when the process that opened it has already gone and closed it with it."
  @spec stop() :: :ok
  def stop do
    case :persistent_term.get(@key, nil) do
      nil ->
        :ok

      device ->
        write(:stop, [])
        File.close(device)
        forget()
    end
  end

  defp forget do
    :persistent_term.erase(@key)
    :ok
  end

  @doc "The events in a trace file, each a map of its fields as strings; lines with no fields are dropped."
  @spec read!(Path.t()) :: [event()]
  def read!(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&fields/1)
    |> Enum.reject(&(&1 == %{}))
  end

  defp fields(line) do
    line
    |> String.split(" ", trim: true)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> Map.put(acc, key, value)
        _other -> acc
      end
    end)
  end

  @doc "An event's time in milliseconds."
  @spec at(event()) :: float()
  def at(%{"t" => t}), do: t |> Float.parse() |> elem(0)

  @doc "How many events of each kind, and for each kind the gaps between one and the next as median, p90, max and count."
  @spec summary([event()]) :: %{
          counts: %{String.t() => non_neg_integer()},
          gaps: %{String.t() => map()}
        }
  def summary(events) do
    by_kind = Enum.group_by(events, & &1["kind"])

    %{
      counts: Map.new(by_kind, fn {kind, list} -> {kind, length(list)} end),
      gaps: Map.new(by_kind, fn {kind, list} -> {kind, stats(gaps(list))} end)
    }
  end

  @doc "The time from each `from` event to the next `to` event after it, as median, p90, max and count."
  @spec latency([event()], String.t(), String.t()) :: map()
  def latency(events, from, to) do
    events
    |> Enum.filter(&(&1["kind"] in [from, to]))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [a, b] -> a["kind"] == from and b["kind"] == to end)
    |> Enum.map(fn [a, b] -> at(b) - at(a) end)
    |> stats()
  end

  @doc "Median, p90, max and count of a list of numbers; zeros for none."
  @spec stats([number()]) :: %{
          median: float(),
          p90: float(),
          max: float(),
          count: non_neg_integer()
        }
  def stats([]), do: %{median: 0.0, p90: 0.0, max: 0.0, count: 0}

  def stats(values) do
    sorted = Enum.sort(values)
    count = length(sorted)

    %{
      median: percentile(sorted, count, 50),
      p90: percentile(sorted, count, 90),
      max: List.last(sorted) / 1,
      count: count
    }
  end

  defp percentile(sorted, count, share),
    do: Enum.at(sorted, min(count - 1, div(count * share, 100))) / 1

  defp gaps(events) do
    events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> at(b) - at(a) end)
  end

  defp path do
    case System.get_env("CAULDRON_TRACE") do
      nil -> nil
      "" -> nil
      "1" -> Path.join(File.cwd!(), "cauldron_trace.log")
      path -> path
    end
  end

  defp format(value) when is_float(value), do: Float.round(value, 2)
  defp format(value), do: value
end
