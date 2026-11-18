defmodule Cauldron.Net.WireTest do
  use ExUnit.Case, async: true

  alias Cauldron.Net.Wire

  test "a join and a push are Phoenix channel V2 arrays, and a reply and a push read back" do
    assert Jason.decode!(Wire.encode("1", "1", "world:main", "phx_join", %{team: 2})) == [
             "1",
             "1",
             "world:main",
             "phx_join",
             %{"team" => 2}
           ]

    assert Jason.decode!(
             Wire.encode("1", "4", "world:main", "input", %{held: ["jump"], aim: nil})
           ) == ["1", "4", "world:main", "input", %{"held" => ["jump"], "aim" => nil}]

    assert {:reply, "1", "1", "world:main", "ok", %{}} =
             Wire.decode(~s|["1","1","world:main","phx_reply",{"status":"ok","response":{}}]|)

    assert {:push, "1", "world:main", "frame", %{"focus" => [1, 2]}} =
             Wire.decode(~s|["1",null,"world:main","frame",{"focus":[1,2]}]|)
  end

  test "a binary push carries its topic, event and bytes" do
    join_ref = "1"
    topic = "world:main"
    event = "pcm"
    data = <<1, 2, 3, 4>>

    bin =
      <<0, byte_size(join_ref), byte_size(topic), byte_size(event), join_ref::binary,
        topic::binary, event::binary, data::binary>>

    assert {:push, "1", "world:main", "pcm", <<1, 2, 3, 4>>} = Wire.decode_binary(bin)

    broadcast =
      <<2, byte_size(topic), byte_size(event), topic::binary, event::binary, data::binary>>

    assert {:push, nil, "world:main", "pcm", <<1, 2, 3, 4>>} = Wire.decode_binary(broadcast)
  end

  test "a status and where to go are read into plain shapes" do
    assert %{focus: {1.0, 2.5}, hud: [[{"coins", "#ffff00"}]], over: nil, subject: nil} =
             Wire.status(%{
               "focus" => [1.0, 2.5],
               "hud" => [[["coins", "#ffff00"]]],
               "over" => nil
             })

    assert %{focus: nil, subject: "bob"} =
             Wire.status(%{"hud" => [], "over" => nil, "subject" => "bob"})

    assert Wire.go(%{"to" => "settings"}) == :settings
  end
end
