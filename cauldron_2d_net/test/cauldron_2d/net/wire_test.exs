defmodule Cauldron2D.Net.WireTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Net.Wire

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

  test "frames, maps and the sheet index are read into the shapes the painter takes" do
    assert %{focus: {1.0, 2.5}, movers: [{3, 4.0, 5.0}], hud: [[{"coins", "#ffff00"}]], over: nil} =
             Wire.frame(%{
               "focus" => [1.0, 2.5],
               "movers" => [[3, 4.0, 5.0]],
               "hud" => [[["coins", "#ffff00"]]],
               "over" => nil
             })

    assert %{width: 2, height: 1, tile: 16, wrap: true, rows: [[0, 1]]} =
             Wire.map(%{
               "width" => 2,
               "height" => 1,
               "tile" => 16,
               "wrap" => true,
               "rows" => [[0, 1]]
             })

    assert %{tile: 16, columns: 16, frames: [{0, 0}, {16, 0}], url: "/atlas.png", anim: %{}} =
             Wire.sheet(%{
               "tile" => 16,
               "columns" => 16,
               "frames" => [[0, 0], [16, 0]],
               "url" => "/atlas.png",
               "arts" => %{}
             })

    assert %{anim: %{1 => %{indices: [1, 2], fps: 4}}} =
             Wire.sheet(%{
               "tile" => 16,
               "columns" => 16,
               "frames" => [],
               "url" => "/a.png",
               "anim" => %{"1" => %{"indices" => [1, 2], "fps" => 4}}
             })
  end
end
