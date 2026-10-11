defmodule QuakeC.ExecTest do
  use ExUnit.Case, async: true

  alias QuakeC.{Exec, Progs}

  defmodule NoBuiltins do
    def call(host, _number, _argc), do: host
  end

  defp progs(globals) do
    functions = {
      %{first: 0, parm_start: 0, locals: 0, name: "", parm_sizes: []},
      %{first: 1, parm_start: 32, locals: 2, name: "double", parm_sizes: [1]},
      %{first: 4, parm_start: 34, locals: 0, name: "main", parm_sizes: []}
    }

    statements = {
      {0, 0, 0, 0},
      {1, 32, 28, 33},
      {43, 33, 0, 0},
      {0, 0, 0, 0},
      {31, 30, 4, 0},
      {52, 31, 0, 0},
      {31, 1, 29, 0},
      {0, 0, 0, 0}
    }

    %Progs{
      statements: statements,
      functions: functions,
      strings: <<0>>,
      globals: globals,
      global_defs: %{"result" => {:float, 29}},
      field_defs: %{},
      entity_fields: 1,
      function_names: %{"double" => 1, "main" => 2}
    }
  end

  test "a call passes its argument in, returns its result, and gives back the caller's view of the callee's locals" do
    globals =
      List.duplicate(0, 35)
      |> List.replace_at(28, 2.0)
      |> List.replace_at(30, 3.0)
      |> List.replace_at(31, 1)
      |> List.replace_at(32, 99.0)

    host = %{qc: QuakeC.new(progs(List.to_tuple(globals)))}

    %{qc: qc} = Exec.call_named(host, "main", NoBuiltins)

    assert QuakeC.slot(qc, 29) == 6.0
    assert QuakeC.slot(qc, 32) == 99.0
  end
end
