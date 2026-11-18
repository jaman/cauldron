defmodule Cauldron.Client.Start do
  @moduledoc """
  Where a client starts, from the launch's `:start` prop or the game's
  `c:Cauldron.Client.Game.start/0`, the same in every front end.

      flow = Cauldron.Client.Start.flow(MyGame.Client, props)
      Cauldron.Client.Start.first_screen(flow)
      #=> :title

  A flow is `:lobby` (the title, then the lobby), `{:lobby, opts}` (`title: false` opens
  on the lobby), `{:play, id, opts}` (straight into world `id` of `worlds/1`, `:first`
  for the first; `title: true` shows the title first) or a function of the client's
  state.
  """

  alias Cauldron.Client.Game

  @type flow ::
          :lobby | {:lobby, keyword()} | {:play, term(), keyword()} | (map() -> map())

  @doc "The flow for `game` launched with `props`."
  @spec flow(module(), map()) :: flow()
  def flow(game, props) do
    case Map.get(props, :start) || Game.optional(game, :start, [], nil) || legacy(game) do
      :title -> :lobby
      :lobby -> :lobby
      {:lobby, opts} -> {:lobby, opts}
      {:play, id} -> {:play, id, []}
      {:play, id, opts} -> {:play, id, opts}
      fun when is_function(fun, 1) -> fun
    end
  end

  @doc "The screen a flow opens on: `:title`, `:lobby`, `:play`, or `:starting` for the game's own."
  @spec first_screen(flow()) :: :title | :lobby | :play | :starting
  def first_screen(:lobby), do: :title

  def first_screen({:lobby, opts}),
    do: if(Keyword.get(opts, :title, true), do: :title, else: :lobby)

  def first_screen({:play, _id, opts}),
    do: if(Keyword.get(opts, :title, false), do: :title, else: :play)

  def first_screen(fun) when is_function(fun, 1), do: :starting

  @doc "Whether leaving the lobby goes to the title (`true`) or ends the client."
  @spec lobby_backs_to_title?(flow()) :: boolean()
  def lobby_backs_to_title?(:lobby), do: true
  def lobby_backs_to_title?({:lobby, opts}), do: Keyword.get(opts, :title, true)
  def lobby_backs_to_title?(_flow), do: false

  defp legacy(game) do
    if Game.optional(game, :lobby?, [], true), do: :lobby, else: {:play, :first, title: true}
  end
end
