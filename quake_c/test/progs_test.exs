defmodule QuakeC.ProgsTest do
  use ExUnit.Case, async: true

  alias QuakeC.Progs

  defp program(version, extra) do
    strings = <<0, "classname", 0, "main", 0>>
    statements = <<0::little-16, 0::16, 0::16, 0::16>>
    global_defs = <<5::little-16, 30::little-16, 1::little-32>>
    field_defs = <<1::little-16, 28::little-16, 1::little-32>>

    functions =
      <<0::little-32, 0::32, 0::32, 0::32, 0::32, 0::32, 0::32, 0::64>> <>
        <<0::little-32, 0::32, 0::32, 0::32, 11::little-32, 0::32, 0::32, 0::64>>

    globals = :binary.copy(<<0::32>>, 30) <> <<28::little-32>>
    header_size = 4 + 4 + 13 * 4 + byte_size(extra)

    lumps = [statements, global_defs, field_defs, functions, strings, globals]

    {offsets, _} =
      Enum.map_reduce(lumps, header_size, fn lump, at -> {at, at + byte_size(lump)} end)

    [s, gd, fd, fns, str, g] = offsets

    <<version::little-32, 0::32, s::little-32, 1::little-32, gd::little-32, 1::little-32,
      fd::little-32, 1::little-32, fns::little-32, 2::little-32, str::little-32,
      byte_size(strings)::little-32, g::little-32, 31::little-32, 40::little-32>> <>
      extra <> IO.iodata_to_binary(lumps)
  end

  test "a version 6 program's field global is an integer offset" do
    {:ok, progs} = Progs.parse(program(6, <<>>))
    assert progs.global_defs["classname"] == {:field, 30}
    assert elem(progs.globals, 30) === 28
    assert Progs.function(progs, "main") == 1
  end

  test "an FTE version 7 program with 16-bit statements reads as version 6 does" do
    secondary = Bitwise.bxor(0x45544631, 0x474F5250)
    extra = :binary.copy(<<0::32>>, 7) <> <<secondary::little-32>>
    {:ok, progs} = Progs.parse(program(7, extra))
    assert progs.global_defs["classname"] == {:field, 30}
    assert elem(progs.globals, 30) === 28
  end
end
