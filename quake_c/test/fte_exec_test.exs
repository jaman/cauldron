defmodule QuakeC.FteExecTest do
  use ExUnit.Case, async: true

  alias QuakeC.{Exec, Progs}

  defmodule Recorder do
    def call(host, 5, argc) do
      parm = &QuakeC.slot_vector(host.qc, &1)
      %{host | args: {argc, parm.(4), parm.(7)}}
    end
  end

  defp host(statements, globals) do
    slots =
      Enum.reduce(globals, List.duplicate(0, 120), fn {at, value}, acc ->
        List.replace_at(acc, at, value)
      end)

    progs = %Progs{
      statements: List.to_tuple([{0, 0, 0, 0} | statements]),
      functions: {
        %{first: 0, parm_start: 0, locals: 0, name: "", parm_sizes: []},
        %{first: 1, parm_start: 110, locals: 0, name: "main", parm_sizes: []},
        %{first: 0, parm_start: 0, locals: 0, name: "", parm_sizes: []},
        %{first: -5, parm_start: 0, locals: 0, name: "record", parm_sizes: []}
      },
      strings: <<0>>,
      globals: List.to_tuple(slots),
      global_defs: %{
        "loaded" => {:float, 54},
        "element" => {:float, 56},
        "picked" => {:float, 90}
      },
      field_defs: %{},
      entity_fields: 4,
      function_names: %{"main" => 1}
    }

    %{qc: QuakeC.new(progs), args: nil}
  end

  defp run(statements, globals),
    do: statements |> host(globals) |> Exec.call_named("main", Recorder)

  test "a field written through its address reads back from the entity" do
    %{qc: qc} =
      run([{30, 50, 51, 53}, {37, 52, 53, 0}, {24, 50, 51, 54}, {0, 0, 0, 0}], %{
        50 => 1,
        51 => 2,
        52 => 7.5
      })

    assert QuakeC.slot(qc, 54) == 7.5
    assert QuakeC.field_slot(qc, 1, 2) == 7.5
  end

  test "an entity field stored by entity and field number lands in that entity" do
    %{qc: qc} = run([{220, 50, 51, 52}, {0, 0, 0, 0}], %{50 => 2, 51 => 3, 52 => 4.25})
    assert QuakeC.field_slot(qc, 2, 3) == 4.25
  end

  test "a pointer into a global array, moved on by whole words, reads the element it reaches" do
    %{qc: qc} =
      run([{143, 40, 60, 53}, {144, 53, 50, 55}, {154, 55, 60, 56}, {0, 0, 0, 0}], %{
        40 => 10.0,
        41 => 20.0,
        42 => 30.0,
        50 => 2
      })

    assert QuakeC.slot(qc, 56) == 30.0
  end

  test "a hexen2-style call passes its second and third operands as the first two arguments" do
    host =
      run([{106, 70, 71, 74}, {0, 0, 0, 0}], %{
        70 => 3,
        71 => 1.0,
        72 => 2.0,
        73 => 3.0,
        74 => 4.0,
        75 => 5.0,
        76 => 6.0
      })

    assert host.args == {2, {1.0, 2.0, 3.0}, {4.0, 5.0, 6.0}}
  end

  test "a switch on a float jumps to the body of the case that matches it" do
    statements = [
      {98, 80, 5, 0},
      {31, 91, 90, 0},
      {0, 0, 0, 0},
      {31, 92, 90, 0},
      {0, 0, 0, 0},
      {103, 81, -4, 0},
      {103, 82, -3, 0},
      {0, 0, 0, 0}
    ]

    %{qc: qc} = run(statements, %{80 => 2.0, 81 => 1.0, 82 => 2.0, 91 => 100.0, 92 => 200.0})
    assert QuakeC.slot(qc, 90) == 200.0
  end
end
