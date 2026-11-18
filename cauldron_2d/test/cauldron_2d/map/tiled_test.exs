defmodule Cauldron2D.Map.TiledTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Map.Tiled

  @flipped_h 0x80000000

  defp tmj(data) do
    JSON.encode!(%{
      "width" => 3,
      "height" => 2,
      "tilewidth" => 16,
      "tileheight" => 16,
      "properties" => [%{"name" => "gravity", "type" => "float", "value" => 9.5}],
      "tilesets" => [%{"firstgid" => 1, "name" => "rock", "columns" => 4, "tilecount" => 16}],
      "layers" => [
        Map.merge(
          %{"type" => "tilelayer", "name" => "ground", "width" => 3, "height" => 2},
          data
        ),
        %{
          "type" => "group",
          "name" => "things",
          "layers" => [
            %{
              "type" => "objectgroup",
              "name" => "spawns",
              "objects" => [
                %{
                  "id" => 1,
                  "name" => "hero",
                  "type" => "start",
                  "x" => 32,
                  "y" => 16,
                  "properties" => [%{"name" => "lives", "type" => "int", "value" => 3}]
                }
              ]
            }
          ]
        }
      ]
    })
  end

  @tmx """
  <?xml version="1.0" encoding="UTF-8"?>
  <map version="1.10" orientation="orthogonal" width="3" height="2" tilewidth="16" tileheight="16">
   <properties><property name="gravity" type="float" value="9.5"/></properties>
   <tileset firstgid="1" name="rock" tilewidth="16" tileheight="16" tilecount="16" columns="4"/>
   <layer id="1" name="ground" width="3" height="2">
    <data encoding="csv">1,0,2,
  0,#{@flipped_h + 3},0</data>
   </layer>
   <group name="things">
    <objectgroup name="spawns">
     <object id="1" name="hero" type="start" x="32" y="16">
      <properties><property name="lives" type="int" value="3"/></properties>
     </object>
    </objectgroup>
   </group>
  </map>
  """

  defp expect(level) do
    ground = Tiled.layer(level, "ground")
    assert ground.tiles == %{{0, 0} => 1, {2, 0} => 2, {1, 1} => 3}
    assert ground.flips == %{{1, 1} => [:horizontal]}
    assert level.properties == %{"gravity" => 9.5}

    assert [%{name: "hero", type: "start", x: 2.0, y: 1.0, properties: %{"lives" => 3}}] =
             Tiled.objects(level, "things/spawns")
  end

  test "a level written as JSON and as XML reads the same" do
    {:ok, from_json} = Tiled.parse(tmj(%{"data" => [1, 0, 2, 0, @flipped_h + 3, 0]}), :tmj)
    expect(from_json)

    {:ok, from_xml} = Tiled.parse(@tmx, :tmx)
    expect(from_xml)
  end

  test "base64 tile data, compressed with zlib, reads the same as a list" do
    bytes = for gid <- [1, 0, 2, 0, @flipped_h + 3, 0], into: <<>>, do: <<gid::little-32>>

    encoded = %{
      "encoding" => "base64",
      "compression" => "zlib",
      "data" => Base.encode64(:zlib.compress(bytes))
    }

    {:ok, level} = Tiled.parse(tmj(encoded), :tmj)
    expect(level)
  end
end
