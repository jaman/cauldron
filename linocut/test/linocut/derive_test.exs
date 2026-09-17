defmodule Linocut.DeriveTest do
  use ExUnit.Case, async: true

  alias Linocut.{Derive, Pic}

  doctest Linocut.Derive

  @knight """
  H #a05000
  C #2040c0
  S #ffd0a0

  .HH.
  SS..
  CCCC
  C..C
  """

  @hat """
  B #000000

  BBBB
  ....
  ....
  ....
  """

  @walk """
  C #2040c0

  C.
  ..
  ---
  .C
  ..
  """

  defp lookup("knight"), do: {:ok, @knight}
  defp lookup("hat"), do: {:ok, @hat}
  defp lookup("walk"), do: {:ok, @walk}
  defp lookup(_name), do: :error

  defp rows(text) do
    {:ok, pic} = Pic.read(text)
    pic.frames
  end

  describe "parse/1" do
    test "every operation, separated by semicolons, in the order written" do
      assert Derive.parse(
               "from knight; colour C #c02020; color H black; swap H S; flip h; flip v; turn 90; shift 1 -1; frame 2; reverse; over hat 0 -2; over hat"
             ) ==
               {:ok,
                [
                  {:from, "knight"},
                  {:colour, "C", "#c02020"},
                  {:colour, "H", "black"},
                  {:swap, "H", "S"},
                  {:flip, :h},
                  {:flip, :v},
                  {:turn, 90},
                  {:shift, 1, -1},
                  {:frame, 2},
                  :reverse,
                  {:over, "hat", 0, -2},
                  {:over, "hat", 0, 0}
                ]}
    end

    test "a derivation starts with from, and an unknown word or a bad argument is named" do
      assert {:error, message} = Derive.parse("flip h")
      assert message =~ "from"
      assert {:error, message} = Derive.parse("from knight; bend 3")
      assert message =~ "bend"
      assert {:error, message} = Derive.parse("from knight; turn 45")
      assert message =~ "45"
    end
  end

  describe "run/2" do
    test "a colour change keeps the picture and changes the palette entry" do
      {:ok, text} = Derive.derive("from knight; colour C #c02020", &lookup/1)
      {:ok, pic} = Pic.read(text)
      assert List.keyfind(pic.palette, "C", 0) == {"C", "#c02020"}
      assert pic.frames == rows(@knight)
    end

    test "swap exchanges what two keys mean" do
      {:ok, text} = Derive.derive("from knight; swap H C", &lookup/1)
      {:ok, pic} = Pic.read(text)
      assert List.keyfind(pic.palette, "H", 0) == {"H", "#2040c0"}
      assert List.keyfind(pic.palette, "C", 0) == {"C", "#a05000"}
    end

    test "flip, turn and shift move the keys" do
      {:ok, flipped} = Derive.derive("from knight; flip h", &lookup/1)
      assert rows(flipped) == [[".HH.", "..SS", "CCCC", "C..C"]]

      {:ok, upside} = Derive.derive("from knight; flip v", &lookup/1)
      assert rows(upside) == [["C..C", "CCCC", "SS..", ".HH."]]

      {:ok, turned} = Derive.derive("from knight; turn 90", &lookup/1)
      assert rows(turned) == [["CCS.", ".CSH", ".C.H", "CC.."]]

      {:ok, around} = Derive.derive("from knight; turn 180", &lookup/1)
      assert rows(around) == [["C..C", "CCCC", "..SS", ".HH."]]

      {:ok, shifted} = Derive.derive("from knight; shift 1 1", &lookup/1)
      assert rows(shifted) == [["....", "..HH", ".SS.", ".CCC"]]
    end

    test "frame picks one of an animation, reverse turns it round" do
      {:ok, second} = Derive.derive("from walk; frame 2", &lookup/1)
      assert rows(second) == [[".C", ".."]]

      {:ok, back} = Derive.derive("from walk; reverse", &lookup/1)
      assert rows(back) == [[".C", ".."], ["C.", ".."]]

      assert {:error, message} = Derive.derive("from walk; frame 3", &lookup/1)
      assert message =~ "3"
    end

    test "over lays another picture on top, its transparent keys letting the picture through, palettes merged" do
      {:ok, text} = Derive.derive("from knight; over hat 0 0", &lookup/1)
      {:ok, pic} = Pic.read(text)
      assert pic.frames == [["BBBB", "SS..", "CCCC", "C..C"]]
      assert List.keyfind(pic.palette, "B", 0) == {"B", "#000000"}

      {:ok, raised} = Derive.derive("from knight; over hat 1 1", &lookup/1)
      assert rows(raised) == [[".HH.", "SBBB", "CCCC", "C..C"]]
    end

    test "a key two pictures use for different colours is refused, and a name nobody knows" do
      assert {:ok, _same} = Derive.derive("from knight; over knight 0 0", &lookup/1)

      {:ok, red} = Derive.derive("from knight; colour C #ff0000", &lookup/1)

      assert {:error, message} =
               Derive.derive("from knight; over red 0 0", fn
                 "red" -> {:ok, red}
                 name -> lookup(name)
               end)

      assert message =~ "C"

      assert {:error, message} = Derive.derive("from ghost", &lookup/1)
      assert message =~ "ghost"
    end
  end
end
