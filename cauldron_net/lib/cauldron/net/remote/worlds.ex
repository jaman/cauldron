defmodule Cauldron.Net.Remote.Worlds do
  @moduledoc """
  Names for worlds that are not in this VM, so a client joins them as it joins any
  `Cauldron.World`: `{:via, Cauldron.Net.Remote.Worlds, name}`.

      {:via, Cauldron.Net.Remote.Worlds, {:node, :"my_game@arcade", :pit}}
      {:via, Cauldron.Net.Remote.Worlds, {:url, "http://arcade:2280", token, "pit", drawer: Cauldron2D.Net.Drawer}}

  A node's world is started on that node when the name is first looked up and is its
  pid from then on; a server's world by URL is a `Cauldron.Net.Link.World` in this
  VM, one per server and world, started on the first lookup, its fifth element the link
  world's options (`:drawer` among them).
  """

  alias Cauldron.Net.{Link, Remote}

  @registry Cauldron.Net.Remote.Registry

  @doc false
  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @registry)

  @doc false
  def register_name(name, pid), do: Registry.register_name({@registry, name}, pid)

  @doc false
  def unregister_name(name), do: Registry.unregister_name({@registry, name})

  @doc false
  def whereis_name({:node, node, id}) do
    case Remote.node_world(node, id) do
      {:ok, pid} -> pid
      {:error, _reason} -> :undefined
    end
  end

  def whereis_name({:url, url, token, world, opts} = name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] ->
        pid

      [] ->
        case Link.World.start(
               [url: url, token: token, world: world, name: {:via, __MODULE__, name}] ++ opts
             ) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
          {:error, _reason} -> :undefined
        end
    end
  end

  @doc false
  def send(name, message) do
    case whereis_name(name) do
      :undefined -> :erlang.error(:badarg, [name, message])
      pid -> Kernel.send(pid, message)
    end
  end
end
