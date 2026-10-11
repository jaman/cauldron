defmodule Cauldron2D.Worlds do
  @moduledoc """
  The worlds a game offers: a `Cauldron2D.World` each, with whatever runs beside it,
  started on the first use of its name and stopped again once no player has been in it
  for a while.

      :ok = Cauldron2D.Worlds.register(:pit, game: MyGame, game_opts: [map: map], name: "The Pit", map: "pit")
      Cauldron2D.Worlds.list()
      Cauldron2D.Player.join(Cauldron2D.Worlds.world_name(:pit), "alice", %{username: "alice"})

  `register/2` makes a world known; `world_name/1` names its process, and any call to
  that name starts the world if it is not running. `Cauldron2D.Worlds.Sweeper` stops
  worlds that have had no human in them for a while and seats missing children again.
  `list/0` is what a lobby shows, running or not, in the shape
  `Cauldron2D.Client.Game`'s `worlds/0` gives.

  ## Options

    * `:game`, `:game_opts`, `:hz`, `:tick`, `:record` — the world's, as
      `Cauldron2D.World.start_link/1` takes them. `:game` is required
    * `:name` — what the lobby calls the world. Default: the id as a string
    * `:map`, `:note`, `:kind`, `:teams` — shown in the lobby, as
      `Cauldron2D.Client.Game`'s world describes them. Default: none
    * `:children` — a function from `%{id: id, world: world_name, humans: count}` to
      child specs started under the world's supervisor beside its process: computer players, a
      `Cauldron2D.Ledger.Recorder`. Called when the world starts and on every
      `reseat/1`; a spec whose id is already running is left alone, one that has
      stopped is started again. Default: none

  A player whose id is `{:robot, n}` is not a human.
  """

  alias Cauldron2D.World
  alias Cauldron2D.Worlds.Table

  @registry Cauldron2D.Worlds.Registry
  @supervisor Cauldron2D.Worlds.Supervisor

  @type id :: term()

  @doc false
  def child_specs do
    [
      {Registry, keys: :unique, name: @registry},
      Table,
      {DynamicSupervisor, strategy: :one_for_one, name: @supervisor}
    ]
  end

  @doc "Make world `id` known without starting it; see the module documentation for the options."
  @spec register(id(), keyword()) :: :ok
  def register(id, opts) do
    unless Keyword.has_key?(opts, :game), do: raise(ArgumentError, "a world needs a :game")
    Table.put(id, %{id: id, opts: opts, listing: listing(id, opts)})
  end

  defp listing(id, opts) do
    opts
    |> Keyword.take([:map, :note, :kind, :teams])
    |> Map.new()
    |> Map.merge(%{id: id, name: Keyword.get(opts, :name, to_string(id)), world: world_name(id)})
  end

  @doc "Register world `id` and start it at once."
  @spec open(id(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(id, opts) do
    with :ok <- register(id, opts), do: start(id)
  end

  @doc "Start registered world `id`; the running world's pid if it already is."
  @spec start(id()) :: {:ok, pid()} | {:error, term()}
  def start(id) do
    case Table.get(id) do
      nil ->
        {:error, :unknown_world}

      %{opts: opts} ->
        case DynamicSupervisor.start_child(@supervisor, world_spec(id, opts)) do
          {:ok, _supervisor} ->
            reseat(id)
            {:ok, running(id)}

          {:error, {:already_started, _supervisor}} ->
            {:ok, running(id)}

          {:error, {:shutdown, {:failed_to_start_child, _child, reason}}} ->
            {:error, reason}

          other ->
            other
        end
    end
  end

  defp world_spec(id, opts) do
    world_opts =
      opts
      |> Keyword.take([:game, :game_opts, :hz, :tick, :record])
      |> Keyword.put(:name, via({:world, id}))

    %{
      id: {:supervisor, id},
      start:
        {Supervisor, :start_link,
         [
           [%{id: :world, start: {World, :start_link, [world_opts]}, restart: :transient}],
           [strategy: :rest_for_one, name: via({:supervisor, id})]
         ]},
      restart: :transient,
      type: :supervisor
    }
  end

  @doc "Start the children world `id` is missing, as its `:children` function gives them now."
  @spec reseat(id()) :: :ok
  def reseat(id) do
    with %{opts: opts} <- Table.get(id),
         children when is_function(children, 1) <- Keyword.get(opts, :children),
         supervisor when is_pid(supervisor) <- whereis({:supervisor, id}) do
      specs = children.(%{id: id, world: world_name(id), humans: length(humans(id))})
      Enum.each(specs, &seat(supervisor, &1))
    else
      _nothing_to_seat -> :ok
    end
  end

  defp seat(supervisor, spec) do
    case Supervisor.start_child(supervisor, spec) do
      {:error, :already_present} -> Supervisor.restart_child(supervisor, spec.id)
      _started_or_running -> :ok
    end
  end

  @doc "The name world `id` runs under; using it starts the world when it is not running."
  @spec world_name(id()) :: GenServer.name()
  def world_name(id), do: {:via, __MODULE__.OnDemand, id}

  @doc """
  The name world `id` of `node` runs under, for a node this one is connected to; using
  it starts the world there when it is not running. A node that cannot be reached names
  no process.
  """
  @spec world_name(id(), node()) :: GenServer.name()
  def world_name(id, node) when node == node(), do: world_name(id)
  def world_name(id, node), do: {:via, __MODULE__.OnDemand, {:on, node, id}}

  @doc "The pid of world `id` while it runs, else `nil`."
  @spec running(id()) :: pid() | nil
  def running(id), do: whereis({:world, id})

  @doc "Whether world `id` is running."
  @spec running?(id()) :: boolean()
  def running?(id), do: running(id) != nil

  @doc "Every registered world, as a lobby lists them, with the humans in each — their count as `players`, their ids as `humans` — by name."
  @spec list() :: [map()]
  def list do
    Table.listings()
    |> Enum.map(fn {id, listing} ->
      humans = humans(id)
      Map.merge(listing, %{players: length(humans), humans: humans})
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc "The ids of every registered world."
  @spec ids() :: [id()]
  def ids, do: for({id, _listing} <- Table.listings(), do: id)

  @doc "The ids of every world that is running."
  @spec running_ids() :: [id()]
  def running_ids, do: Registry.select(@registry, [{{{:world, :"$1"}, :_, :_}, [], [:"$1"]}])

  @doc "The players in world `id` who are not robots; `[]` while it is not running."
  @spec humans(id()) :: [term()]
  def humans(id) do
    case running(id) do
      nil -> []
      pid -> pid |> players() |> Enum.reject(&match?({:robot, _}, &1))
    end
  end

  defp players(pid) do
    World.players(pid)
  catch
    :exit, _stopped_meanwhile -> []
  end

  @doc "Stop world `id` and its children, keeping it registered."
  @spec stop(id()) :: :ok
  def stop(id) do
    case whereis({:supervisor, id}) do
      nil -> :ok
      supervisor -> DynamicSupervisor.terminate_child(@supervisor, supervisor)
    end

    :ok
  end

  @doc "Stop world `id` and forget it."
  @spec close(id()) :: :ok
  def close(id) do
    stop(id)
    Table.delete(id)
  end

  @doc false
  def via(key), do: {:via, Registry, {@registry, key}}

  defp whereis(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end
end
