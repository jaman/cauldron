defmodule Catalog.App do
  @moduledoc """
  Every control of `CauldronNative.UI`, as the platforms' own component catalogs show
  theirs: a tab of component screens and a gallery, with the settings in a sheet. Each screen is drawn by
  SwiftUI on iOS and by Jetpack Compose on Android.

  Launched with `CATALOG_OPEN` set to a screen's name (`buttons`, `selection`, …) the
  catalog opens on that screen.
  """

  use CauldronNative.App

  alias Catalog.Screens
  alias CauldronNative.{Device, Location, Notifications}
  alias CauldronNative.Location.Reading

  @song "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"

  @impl true
  def mount(_params) do
    :timer.send_interval(250, :tick)

    %{
      tab: :catalog,
      screens: opened(System.get_env("CATALOG_OPEN")),
      name: "",
      email: "",
      password: "",
      notes: "",
      submitted: nil,
      wifi: true,
      volume: 0.4,
      guests: 2,
      size: :m,
      flavour: :vanilla,
      transport: :bike,
      day: ~D[2026-10-23],
      time: ~T[09:30:00],
      moment: ~N[2026-10-23 18:00:00],
      progress: 0.0,
      expanded: false,
      sheet: false,
      alert: false,
      confirm: false,
      query: "",
      fruits: ["Apple", "Banana", "Cherry", "Grape", "Lemon", "Mango", "Peach", "Pear"],
      chips: MapSet.new([:coffee]),
      favourite: false,
      meter: 0.6,
      settings: false,
      picked: [],
      recording: false,
      recorded: nil,
      camera: false,
      facing: :back,
      answer: "Nothing yet",
      reading: nil,
      following: false,
      map_style: :standard,
      map_note: "Tap a marker, or move the map",
      notified: 0,
      posture: nil,
      last: "Nothing yet"
    }
  end

  @impl true
  def render(state) do
    tabs(
      [
        tab(
          "Catalog",
          [navigation(Enum.map(state.screens, &Screens.page(&1, state)), on_back: :back)],
          id: :catalog,
          icon: :list
        ),
        tab("Gallery", [navigation([Screens.gallery(state)])], id: :gallery, icon: :star)
      ],
      selected: state.tab,
      on_select: :tab
    )
  end

  @impl true
  def handle_event(:tab, tab, state), do: %{state | tab: tab}
  def handle_event({:open, screen}, _value, state), do: %{state | screens: [:home, screen]}
  def handle_event(:back, depth, state), do: %{state | screens: Enum.take(state.screens, depth)}
  def handle_event({:set, key}, value, state), do: noted(Map.put(state, key, value), key, value)
  def handle_event({:show, key}, _value, state), do: Map.put(state, key, true)
  def handle_event({:hide, key}, _value, state), do: Map.put(state, key, false)

  def handle_event({:pressed, what}, _value, state),
    do: %{state | last: "Pressed #{what}", alert: false, confirm: false}

  def handle_event({:chip, chip}, _value, state) do
    chips =
      if MapSet.member?(state.chips, chip),
        do: MapSet.delete(state.chips, chip),
        else: MapSet.put(state.chips, chip)

    %{state | chips: chips}
  end

  def handle_event(:submit, text, state), do: %{state | submitted: text}
  def handle_event(:favourite, _value, state), do: %{state | favourite: not state.favourite}

  def handle_event({:remove, fruit}, _value, state),
    do: %{state | fruits: List.delete(state.fruits, fruit)}

  def handle_event(:restore, _value, state), do: %{state | fruits: mount(%{}).fruits}

  def handle_event({:haptic, style}, _value, state) do
    Device.haptic(style)
    state
  end

  def handle_event({:device, :pick_photos}, _value, state),
    do: asked(state, Device.pick_photos(:picked, limit: 3, videos: true))

  def handle_event({:device, :take_photo}, _value, state),
    do: asked(state, Device.take_photo(:picked))

  def handle_event({:device, :record_video}, _value, state),
    do: asked(state, Device.record_video(:picked))

  def handle_event({:device, :pick_files}, _value, state),
    do: asked(state, Device.pick_files(:picked))

  def handle_event(:record, _value, %{recording: true} = state) do
    Device.stop_recording()
    %{state | recording: false}
  end

  def handle_event(:record, _value, state) do
    Device.start_recording(:recorded)
    %{state | recording: true}
  end

  def handle_event({:play, :recording}, _value, state),
    do: asked(state, Device.play(:played, state.recorded, title: "Recording"))

  def handle_event({:play, :song}, _value, state),
    do:
      asked(state, Device.play(:played, @song, title: "SoundHelix Song 1", artist: "SoundHelix"))

  def handle_event({:playback, action}, _value, state), do: asked(state, Device.playback(action))

  def handle_event(:camera, true, state) do
    Device.permission(:camera, :camera)
    %{state | camera: true}
  end

  def handle_event(:camera, false, state), do: %{state | camera: false}

  def handle_event({:permission, name}, _value, state),
    do: asked(state, Device.permission({:permission, name}, name))

  def handle_event({:share, :text}, _value, state),
    do: asked(state, Device.share("Made with Cauldron: https://github.com/jaman/cauldron"))

  def handle_event({:share, :photo}, _value, state),
    do: asked(state, Device.share(file: List.last(state.picked)))

  def handle_event(:locate, _value, state), do: asked(state, Location.current(:here))

  def handle_event(:follow, true, state),
    do: asked(%{state | following: true}, Location.watch(:follow, distance: 5))

  def handle_event(:follow, false, state), do: asked(%{state | following: false}, Location.stop())
  def handle_event(:place, id, state), do: %{state | map_note: "Chose #{inspect(id)}"}

  def handle_event(:moved, region, state),
    do: %{
      state
      | map_note:
          "Moved to #{Float.round(region.latitude, 4)}, #{Float.round(region.longitude, 4)}, #{round(region.distance)} m across"
    }

  def handle_event({:notify, seconds}, _value, state) do
    count = state.notified + 1
    Notifications.schedule({:note, count}, "Catalog", "Notification #{count}", after: seconds)
    %{state | notified: count}
  end

  def handle_event(:cancel_notification, _value, state),
    do: asked(state, Notifications.cancel({:note, state.notified}))

  def handle_event(:push, _value, state), do: asked(state, Notifications.register_push(:push))

  def handle_event(:open_url, _value, state),
    do: asked(state, Device.open_url("https://elixir-lang.org"))

  @impl true
  def handle_info(:tick, state) do
    next = state.progress + 0.02
    %{state | progress: if(next > 1.0, do: 0.0, else: Float.round(next, 2))}
  end

  def handle_info({:device, tag, answer} = message, state),
    do: message |> answered(state) |> Map.put(:answer, "#{inspect(tag)}: #{inspect(answer)}")

  def handle_info({:cauldron_native, :posture, posture}, state), do: %{state | posture: posture}

  def handle_info(_message, state), do: state

  defp answered({:device, :picked, {:ok, paths}}, state), do: %{state | picked: List.wrap(paths)}

  defp answered({:device, tag, {:ok, %Reading{} = reading}}, state) when tag in [:here, :follow],
    do: %{state | reading: reading}

  defp answered({:device, :recorded, {:ok, path}}, state), do: %{state | recorded: path}
  defp answered({:device, :recorded, _failed}, state), do: %{state | recording: false}
  defp answered(_message, state), do: state

  defp asked(state, :ok), do: state

  defp opened(nil), do: [:home]
  defp opened(name), do: [:home, String.to_existing_atom(name)]

  defp noted(state, key, value), do: %{state | last: "#{key} → #{inspect(value)}"}
end
