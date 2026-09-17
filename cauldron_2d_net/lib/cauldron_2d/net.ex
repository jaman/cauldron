defmodule Cauldron2D.Net do
  @moduledoc """
  A `cauldron_2d` world in a browser, and the links an Elixir client uses to join a
  served world.

  | | |
  |---|---|
  | `Cauldron2D.Net.Pages` | the pages around the worlds, from a `Cauldron2D.Client.Game` |
  | `Cauldron2D.Net.Socket`, `Cauldron2D.Net.Channel` | the player socket and channel |
  | `Cauldron2D.Net.Api` | tokens, arenas, stats and boards over plain HTTP |
  | `Cauldron2D.Net.Session` | a player's life on a channel |
  | `Cauldron2D.Net.Sheet`, `Cauldron2D.Net.Frame`, `Cauldron2D.Net.Wire` | what goes over the wire |
  | `Cauldron2D.Net.Remote`, `Cauldron2D.Net.Remote.Worlds`, `Cauldron2D.Net.Link.World` | a server's arenas from elsewhere |
  | `Cauldron2D.Net.Link.Socket`, `Cauldron2D.Net.Link.Local`, `Cauldron2D.Net.Sound` | an Elixir client's connection and speaker |
  | `Cauldron2D.Net.Load` | a load test against a server |
  """
end
