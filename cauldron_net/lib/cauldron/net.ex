defmodule Cauldron.Net do
  @moduledoc """
  A Cauldron world on the network, whatever the game draws with: the channel and socket
  browsers join through, the sessions behind them, and the links an Elixir client joins a
  world by. What a client is sent to show each scene is a `Cauldron.Net.Drawer`'s;
  `cauldron_2d_net` has the 2D one.

  | | |
  |---|---|
  | `Cauldron.Net.Socket`, `Cauldron.Net.Channel` | the player socket and channel |
  | `Cauldron.Net.Api` | tokens, worlds, stats and boards over plain HTTP |
  | `Cauldron.Net.Session`, `Cauldron.Net.FrontSession` | a player's life on a channel, in a world or on one of the game's screens |
  | `Cauldron.Net.Drawer` | what a client is sent to show a scene, and what it makes of it |
  | `Cauldron.Net.Frame`, `Cauldron.Net.Wire` | a frame's status, and the channel protocol as an Elixir client speaks it |
  | `Cauldron.Net.Audio` | the sound policy, and music shared by a world's players |
  | `Cauldron.Net.Remote`, `Cauldron.Net.Remote.Worlds`, `Cauldron.Net.Link.World` | a server's worlds from elsewhere |
  | `Cauldron.Net.Link.Socket`, `Cauldron.Net.Link.Local`, `Cauldron.Net.Sound` | an Elixir client's connection and speaker |
  | `Cauldron.Net.Load` | a load test against a server |
  """
end
