defmodule Mix.Tasks.Cauldron.Input do
  @moduledoc """
  Measure drafter's input path from a `DRAFTER_TRACE` log.

      DRAFTER_TRACE=1 mix my_game
      mix cauldron.input                 # reads ./drafter_trace.log
      mix cauldron.input /tmp/other.log

  Takes the log path as its one optional argument, defaulting to `drafter_trace.log` in the
  current directory, and raises if it cannot be read. Lines it does not recognise are ignored.

  ## The log

  drafter writes one line per event, `<kind> <hh:mm:ss.uuuuuu> <rest>`:

    * `S` — a chunk read from stdin, ending in the bytes as hex
    * `I` — a decoded event, such as a mouse report
    * `W` — a frame written to the terminal, with `bytes=`, `lines=` and `write_us=` fields

  ## What it prints

  Counts of chunks, decoded events and mouse events, then median, p90 and max for the bytes
  per read, the delay from a chunk arriving to the event it becomes, the gap between reads, and
  the gap between mouse events. For the writes it prints bytes and lines per frame and the time
  spent inside the write call, plus a count of writes over 5 ms, which is time the terminal
  spent not draining what it was sent.
  """
  @shortdoc "Measure drafter's stdin path from a trace log"

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    path = List.first(argv) || Path.join(File.cwd!(), "drafter_trace.log")

    case File.read(path) do
      {:ok, contents} -> contents |> lines() |> report()
      {:error, reason} -> Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp lines(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse/1)
  end

  defp parse(line) do
    case String.split(line, " ", parts: 3) do
      [kind, time, rest] when kind in ["S", "I", "W"] ->
        case at(time) do
          nil -> []
          ms -> [{kind, ms, rest}]
        end

      _other ->
        []
    end
  end

  defp at(time) do
    with [h, m, s] <- String.split(time, ":"),
         {hours, _} <- Integer.parse(h),
         {minutes, _} <- Integer.parse(m),
         {seconds, _} <- Float.parse(s) do
      (hours * 3600 + minutes * 60 + seconds) * 1000
    else
      _ -> nil
    end
  end

  defp report(events) do
    bytes = for {"S", ms, hex} <- events, do: {ms, String.trim(hex)}
    inputs = for {"I", ms, payload} <- events, do: {ms, payload}
    mice = Enum.filter(inputs, fn {_ms, payload} -> payload =~ "mouse" end)

    Mix.shell().info(
      "#{length(bytes)} stdin chunks, #{length(inputs)} decoded events " <>
        "(#{length(mice)} mouse)"
    )

    sizes =
      Enum.map(bytes, fn {_ms, rest} ->
        rest |> String.split() |> List.last() |> to_string() |> String.length() |> div(2)
      end)

    if sizes != [] do
      Mix.shell().info("  bytes per read            #{stats(sizes, "")}")
    end

    if bytes != [] and inputs != [] do
      Mix.shell().info(
        "  chunk -> decoded event    #{stats(decode_latency(bytes, inputs), "ms")}"
      )
    end

    if length(bytes) > 1 do
      Mix.shell().info(
        "  gap between reads         #{stats(gaps(Enum.map(bytes, &elem(&1, 0))), "ms")}"
      )
    end

    if length(mice) > 1 do
      Mix.shell().info(
        "  gap between mouse events  #{stats(gaps(Enum.map(mice, &elem(&1, 0))), "ms")}"
      )
    end

    writes(events)
  end

  defp writes(events) do
    frames = for {"W", ms, payload} <- events, do: {ms, payload}

    if frames != [] do
      Mix.shell().info("#{length(frames)} frames written")
      Mix.shell().info("  bytes per frame           #{stats(field(frames, "bytes"), "")}")
      Mix.shell().info("  lines per frame           #{stats(field(frames, "lines"), "")}")
      Mix.shell().info("  time inside the write     #{stats(field(frames, "write_us"), "us")}")

      blocked = Enum.filter(field(frames, "write_us"), &(&1 > 5_000))

      if blocked != [] do
        total = blocked |> Enum.sum() |> div(1000)

        Mix.shell().info(
          "  writes over 5ms           #{length(blocked)}, #{total}ms spent waiting on the terminal"
        )
      end
    end
  end

  defp field(frames, key) do
    pattern = ~r/#{key}=(\d+)/

    Enum.flat_map(frames, fn {_ms, payload} ->
      case Regex.run(pattern, payload, capture: :all_but_first) do
        [value] -> [String.to_integer(value)]
        _ -> []
      end
    end)
  end

  defp decode_latency(bytes, inputs) do
    Enum.reduce(inputs, {bytes, []}, fn {event_ms, _payload}, {pending, acc} ->
      {before, rest} = Enum.split_while(pending, fn {ms, _hex} -> ms <= event_ms end)

      case before do
        [] -> {rest, acc}
        [{first_ms, _} | _] -> {rest, [event_ms - first_ms | acc]}
      end
    end)
    |> elem(1)
  end

  defp gaps(times) do
    times
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> b - a end)
  end

  defp stats([], _unit), do: "no samples"

  defp stats(values, unit) do
    sorted = Enum.sort(values)

    "median #{pick(sorted, 0.5)}#{unit}  p90 #{pick(sorted, 0.9)}#{unit}  " <>
      "max #{pick(sorted, 1.0)}#{unit}  (n=#{length(sorted)})"
  end

  defp pick(sorted, quantile) do
    index = min(length(sorted) - 1, trunc(length(sorted) * quantile))

    case Enum.at(sorted, index) do
      value when is_float(value) -> Float.round(value, 1)
      value -> value
    end
  end
end
