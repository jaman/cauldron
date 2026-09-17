defmodule Mix.Tasks.Cauldron.Report do
  @shortdoc "Summarise a trace written by Cauldron2D.Trace"

  @moduledoc """
  Summarise a trace written by `Cauldron2D.Trace`.

      CAULDRON_TRACE=1 mix my_game        # play, then quit
      mix cauldron.report                 # reads ./cauldron_trace.log
      mix cauldron.report /tmp/run.log --from mouse --to paddle_start

  Prints how many events of each kind there were and, for each kind, the median, p90
  and longest gap between one and the next in milliseconds. With `--from` and `--to`,
  also the time from each `from` event to the next `to` event: how long the game took
  to answer.
  """

  use Mix.Task

  alias Cauldron2D.Trace

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} = OptionParser.parse(args, strict: [from: :string, to: :string])
    path = List.first(paths, Path.join(File.cwd!(), "cauldron_trace.log"))
    events = Trace.read!(path)
    summary = Trace.summary(events)

    Mix.shell().info("#{path}: #{length(events)} events")

    for {kind, count} <- Enum.sort_by(summary.counts, &(-elem(&1, 1))) do
      Mix.shell().info(
        "  #{String.pad_trailing(kind, 16)} #{String.pad_leading(Integer.to_string(count), 6)}   gaps #{line(summary.gaps[kind])}"
      )
    end

    case {opts[:from], opts[:to]} do
      {from, to} when is_binary(from) and is_binary(to) ->
        Mix.shell().info("  #{from} -> #{to}   #{line(Trace.latency(events, from, to))}")

      _none ->
        :ok
    end
  end

  defp line(%{count: 0}), do: "none"

  defp line(%{median: median, p90: p90, max: max, count: count}),
    do:
      "median #{Float.round(median, 1)}ms  p90 #{Float.round(p90, 1)}ms  max #{Float.round(max, 1)}ms  (#{count})"
end
