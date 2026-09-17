defmodule Cauldron2D.Net.SocketTest do
  use ExUnit.Case, async: true

  defmodule Verify do
    @moduledoc false
    def verify(%{"token" => "good"}),
      do: {:ok, %{username: "alice", settings: %{sfx: 0.5, music: 0.1}}}

    def verify(_params), do: :error
  end

  defmodule Channel do
    @moduledoc false
  end

  defmodule Socket do
    @moduledoc false
    use Cauldron2D.Net.Socket, channel: Channel, verify: {Verify, :verify}
  end

  test "a good token connects with the player's name and settings, a bad one does not" do
    socket = %Phoenix.Socket{}
    assert {:ok, connected} = Socket.connect(%{"token" => "good"}, socket, %{})
    assert connected.assigns.username == "alice"
    assert connected.assigns.settings == %{sfx: 0.5, music: 0.1}
    assert connected.assigns.sheet_url == "/atlas.png"
    assert Socket.id(connected) == "player:alice"
    assert :error = Socket.connect(%{"token" => "bad"}, socket, %{})
  end

  test "the channel answers the topic prefix" do
    assert {Channel, _opts} = Socket.__channel__("world:pit")
  end
end
