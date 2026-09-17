defmodule Cauldron2D.Net.Remote.Worlds do
  @moduledoc """
  Names for worlds that are not in this VM, so a client joins them as it joins any
  `Cauldron2D.World`: `{:via, Cauldron2D.Net.Remote.Worlds, name}`.

      {:via, Cauldron2D.Net.Remote.Worlds, {:node, :"my_game@arcade", :pit}}
      {:via, Cauldron2D.Net.Remote.Worlds, {:url, "http://arcade:2280", token, "pit"}}

  A node's world is started on that node when the name is first looked up and is its
  pid from then on; a server's world by URL is a `Cauldron2D.Net.Link.World` in this
  VM, one per server and arena, started on the first lookup. A URL name may carry a
  fifth element, options for the link world.
  """

  alias Cauldron2D.Net.{Link, Remote}

  @registry Cauldron2D.Net.Remote.Registry

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

  def whereis_name({:url, url, token, arena}), do: whereis_name({:url, url, token, arena, []})

  def whereis_name({:url, url, token, arena, opts} = name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] ->
        pid

      [] ->
        case Link.World.start(
               [url: url, token: token, arena: arena, name: {:via, __MODULE__, name}] ++ opts
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
