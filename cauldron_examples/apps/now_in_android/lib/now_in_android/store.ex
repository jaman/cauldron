defmodule NowInAndroid.Store do
  @moduledoc """
  What the user has chosen, kept in one process and saved to a DETS file in the app's
  data folder (`CAULDRON_NATIVE_DATA`, or `~/.now_in_android` off the device): the topics
  they follow, the news they saved and read, whether they finished choosing topics, their
  recent searches, and their theme (`:brand` `:default` or `:android`, `:dynamic_color`,
  `:dark` `:system`, `:light` or `:dark`).
  """

  use GenServer

  @defaults %{
    followed: MapSet.new(),
    saved: MapSet.new(),
    viewed: MapSet.new(),
    onboarded: false,
    searches: [],
    brand: :default,
    dynamic_color: true,
    dark: :system
  }

  @doc "Start the store, registered under its module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The user's data, as the module describes it."
  @spec user() :: map()
  def user, do: GenServer.call(__MODULE__, :user)

  @doc "Follow the topic `id`, or stop following it."
  @spec toggle_follow(String.t()) :: map()
  def toggle_follow(id), do: change(&%{&1 | followed: toggled(&1.followed, id)})

  @doc "Save the news resource `id`, or unsave it."
  @spec toggle_saved(pos_integer()) :: map()
  def toggle_saved(id), do: change(&%{&1 | saved: toggled(&1.saved, id)})

  @doc "Mark the news resource `id` read."
  @spec read(pos_integer()) :: map()
  def read(id), do: change(&%{&1 | viewed: MapSet.put(&1.viewed, id)})

  @doc "Finish choosing topics, hiding the For You screen's topic picker."
  @spec finish_onboarding() :: map()
  def finish_onboarding, do: change(&%{&1 | onboarded: true})

  @doc "Remember `text` as the newest recent search, keeping the last five."
  @spec searched(String.t()) :: map()
  def searched(text),
    do: change(&%{&1 | searches: Enum.take(Enum.uniq([text | &1.searches]), 5)})

  @doc "Forget the recent searches."
  @spec clear_searches() :: map()
  def clear_searches, do: change(&%{&1 | searches: []})

  @doc "Set the theme setting `key` (`:brand`, `:dynamic_color`, `:dark`) to `value`."
  @spec set(:brand | :dynamic_color | :dark, term()) :: map()
  def set(key, value) when key in [:brand, :dynamic_color, :dark],
    do: change(&Map.put(&1, key, value))

  @impl GenServer
  def init(opts) do
    file = Keyword.get_lazy(opts, :file, &default_file/0)
    File.mkdir_p!(Path.dirname(file))
    {:ok, table} = :dets.open_file(__MODULE__, file: String.to_charlist(file))

    user =
      case :dets.lookup(table, :user) do
        [{:user, user}] -> Map.merge(@defaults, user)
        [] -> @defaults
      end

    {:ok, %{table: table, user: user}}
  end

  @impl GenServer
  def handle_call(:user, _from, state), do: {:reply, state.user, state}

  def handle_call({:change, update}, _from, state) do
    user = update.(state.user)
    :ok = :dets.insert(state.table, {:user, user})
    :ok = :dets.sync(state.table)
    {:reply, user, %{state | user: user}}
  end

  @impl GenServer
  def terminate(_reason, state), do: :dets.close(state.table)

  defp change(update), do: GenServer.call(__MODULE__, {:change, update})

  defp toggled(set, item),
    do: if(MapSet.member?(set, item), do: MapSet.delete(set, item), else: MapSet.put(set, item))

  defp default_file do
    folder =
      System.get_env("CAULDRON_NATIVE_DATA") || Path.join(System.user_home!(), ".now_in_android")

    Path.join(folder, "now_in_android.dets")
  end
end
