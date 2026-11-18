defmodule CauldronNative.App do
  @moduledoc """
  An app whose screens are the platform's own controls, SwiftUI on iOS and Jetpack Compose
  on Android, with its state and logic in Elixir on the device.

      defmodule Notes.App do
        use CauldronNative.App

        @impl true
        def mount(_params), do: %{notes: [], draft: ""}

        @impl true
        def render(state) do
          navigation([
            screen("Notes", [
              list(for {note, i} <- Enum.with_index(state.notes), do: text(note, id: i)),
              text_field("New note", value: state.draft, on_change: :draft, on_submit: :add),
              button("Add", on_tap: :add, disabled: state.draft == "")
            ])
          ])
        end

        @impl true
        def handle_event(:draft, text, state), do: %{state | draft: text}
        def handle_event(:add, _value, state), do: %{state | notes: [state.draft | state.notes], draft: ""}
      end

  An app with nothing else to start is named in the project's config, and the release
  starts it on launch:

      config :cauldron_native, app: Notes.App

  An app whose screens read processes of its own (a store, a cache) starts it in its own
  supervision tree after them instead, so they are running before its first `mount/1`:

      children = [FoodTruck.Store, FoodTruck.App]

  `use CauldronNative.App` gives the module a `child_spec/1` for this, which takes
  `params:` for `mount/1`. Outside a native app the child starts nothing (`:ignore`), so
  the same tree runs in tests and on a desktop.

  After each event or message the app's `render/1` is called again; the platform is sent
  only the controls that changed (`CauldronNative.UI.Tree`). `use CauldronNative.App`
  imports `CauldronNative.UI`.
  """

  alias CauldronNative.UI.Node

  @doc "The app's first state, from the `:params` of the config (default `%{}`)."
  @callback mount(params :: map()) :: term()

  @doc "The screen for `state`: one node, holding the rest."
  @callback render(state :: term()) :: Node.t()

  @doc "The state after the event a control named (`on_tap: event`), with the control's value."
  @callback handle_event(event :: term(), value :: term(), state :: term()) :: term()

  @doc """
  The state after any other message the app's process receives: a timer of its own, a
  PubSub broadcast, or `{:cauldron_native, :lifecycle, :active | :inactive | :background}`.
  Optional; without it such messages leave the state as it is.
  """
  @callback handle_info(message :: term(), state :: term()) :: term()

  @optional_callbacks handle_info: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour CauldronNative.App
      import CauldronNative.UI

      @doc "The child spec that runs this app's screens (`CauldronNative.App.Runtime`)."
      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start:
            {CauldronNative.App.Runtime, :start_link,
             [
               [
                 app: __MODULE__,
                 params: Keyword.get(opts, :params, %{}),
                 name: CauldronNative.App.Runtime
               ]
             ]}
        }
      end

      defoverridable child_spec: 1
    end
  end
end
