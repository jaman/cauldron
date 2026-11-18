defmodule CauldronNative.Location do
  @moduledoc """
  The phone's position, from Core Location on iOS and Android's location manager (the
  fused provider where the phone has one). Needs the `:location` permission named in the
  app's config; asking for a position asks for the permission first if it was never
  asked.

  Answers arrive as `CauldronNative.Device`'s do, `{:device, tag, answer}`, the position
  a `CauldronNative.Location.Reading`:

      def handle_event(:where, _value, state) do
        CauldronNative.Location.current(:here)
        state
      end

      def handle_info({:device, :here, {:ok, reading}}, state), do: %{state | here: reading}
      def handle_info({:device, :here, {:error, _reason}}, state), do: state

  When the phone has no fresh position, Android answers with the last one it knew; a
  reading's `time` says when it was measured.

  Errors are `:denied` (the user said no), `:not_declared` (the app's config does not
  name `:location`) and `:unavailable` (the phone could not find itself).

  Options for both requests: `precise` — `true` (default) for the best position the
  phone can give, `false` for a rough one that costs less battery.
  """

  alias CauldronNative.Device.Request

  @doc "One position, answered `{:ok, reading}` once."
  @spec current(term(), keyword()) :: :ok
  def current(tag, opts \\ []), do: Request.send(tag, "location", options(opts))

  @doc """
  Positions as the phone moves, each answered `{:ok, reading}` to `tag`, until `stop/0`.
  A second `watch/2` replaces the first. Option `distance`: metres moved between readings
  (default `10`). On tvOS, where the device stays put, it answers one reading.
  """
  @spec watch(term(), keyword()) :: :ok
  def watch(tag, opts \\ []),
    do:
      Request.send(
        tag,
        "location_watch",
        Map.put(options(opts), :distance, Keyword.get(opts, :distance, 10))
      )

  @doc "Stop the readings `watch/2` began."
  @spec stop() :: :ok
  def stop, do: Request.send(nil, "location_stop", %{})

  defp options(opts), do: %{precise: Keyword.get(opts, :precise, true)}
end
