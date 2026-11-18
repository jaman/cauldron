defmodule Cauldron2D.Net do
  @moduledoc """
  A `cauldron_2d` world in a browser: the drawer that sends its scenes over
  `cauldron_net`'s channels and links, the pages that draw them, and a server for a game
  in one line.

  | | |
  |---|---|
  | `Cauldron2D.Net.Drawer`, `Cauldron2D.Net.Reader` | a 2D scene as it goes to a client, and as a client reads it |
  | `Cauldron2D.Net.Pages` | the pages around the worlds, from a `Cauldron2D.Client.Game` |
  | `Cauldron2D.Net.Serve` | a game served with no web code of its own |
  | `Cauldron2D.Net.Drawing`, `Cauldron2D.Net.Drawn` | who draws, and the pushes that show a scene |
  | `Cauldron2D.Net.Atlas`, `Cauldron2D.Net.Scene`, `Cauldron2D.Net.Picture`, `Cauldron2D.Net.Wire` | what goes over the wire |
  | `Cauldron2D.Net.RemoteScene` | a remote world's view drawn as a scene |
  """
end
