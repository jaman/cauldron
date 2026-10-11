defmodule QuakeC.Progs do
  @moduledoc """
  A compiled QuakeC program, `progs.dat`, read: Quake's version 6, and FTE's version 7 with
  16- or 32-bit statements.

    * `statements` — a tuple of `{op, a, b, c}`; jump distances are signed
    * `functions` — a tuple of `%{first:, parm_start:, locals:, name:, parm_sizes:}`;
      `first` below zero is builtin number `-first`, and 0 a builtin bound by its name
    * `strings` — the string table; a string value is an offset into it
    * `texts` — `%{offset => string}` for every string starting in the table
    * `globals` — the initial global values, a tuple of floats and integers by slot
    * `global_defs`, `field_defs` — `%{name => {type, offset}}`, `type` one of `:void`,
      `:string`, `:float`, `:vector`, `:entity`, `:field`, `:function`, `:pointer`,
      `:integer`
    * `entity_fields` — how many slots an entity's fields take
    * `function_names` — `%{name => index}`
    * `digest` — the SHA-256 of the file, naming the program (and its replacements, `replace/2`)
    * `crc` — the header's check value of the program's global and field layout: 5927
      for Quake's, 54730 for QuakeWorld's
  """

  @enforce_keys [
    :statements,
    :functions,
    :strings,
    :globals,
    :global_defs,
    :field_defs,
    :entity_fields,
    :function_names
  ]
  defstruct [
    :digest,
    :crc,
    :texts,
    :statements,
    :functions,
    :strings,
    :globals,
    :global_defs,
    :field_defs,
    :entity_fields,
    :function_names
  ]

  @type t :: %__MODULE__{}

  @types {:void, :string, :float, :vector, :entity, :field, :function, :pointer, :integer,
          :integer}
  @fte16 Bitwise.bxor(0x45544631, 0x474F5250)
  @fte32 Bitwise.bxor(0x45544631, 0x20423233)
  @jump_b [49, 50, 98, 99, 100, 101, 102, 103, 136, 137, 215, 217, 218]

  @doc "The program in `data`, the bytes of a `progs.dat`."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_progs | :compressed}
  def parse(<<6::little-32, crc::little-32, header::binary-size(52), _::binary>> = data),
    do: {:ok, %{build(data, header, 16) | crc: crc}}

  def parse(
        <<7::little-32, crc::little-32, header::binary-size(52), _::binary-size(24),
          compressed::little-32, secondary::little-signed-32, _::binary>> = data
      )
      when secondary in [@fte16, @fte32] do
    if compressed == 0,
      do: {:ok, %{build(data, header, if(secondary == @fte32, do: 32, else: 16)) | crc: crc}},
      else: {:error, :compressed}
  end

  def parse(_data), do: {:error, :not_progs}

  @doc "The string at offset `offset` of the table."
  @spec string(t(), non_neg_integer()) :: String.t()
  def string(%__MODULE__{texts: texts, strings: strings}, offset) do
    case texts do
      %{^offset => text} -> text
      _ -> string_at(strings, offset)
    end
  end

  @doc "The index of function `name`, or `nil`."
  @spec function(t(), String.t()) :: non_neg_integer() | nil
  def function(%__MODULE__{function_names: names}, name), do: Map.get(names, name)

  @doc """
  The program with each function of `names` run by the host in place of its QuakeC body:
  the function becomes a builtin bound by its name (`first` 0), so every call of it,
  from the program or from `QuakeC.Exec`, runs `builtins.call(host, name, argc)` with the
  arguments in the parameter slots. A name the program lacks is passed over. The
  program's `digest` names the replacements too, so its compiled code is its own.

      progs = QuakeC.Progs.replace(progs, ["Player::UseDown"])
  """
  @spec replace(t(), [String.t()]) :: t()
  def replace(%__MODULE__{} = progs, names) do
    case names |> Enum.map(&function(progs, &1)) |> Enum.reject(&is_nil/1) do
      [] -> progs
      indexes -> replace_indexes(progs, indexes)
    end
  end

  defp replace_indexes(progs, indexes) do
    functions =
      Enum.reduce(indexes, progs.functions, fn index, functions ->
        put_elem(functions, index, %{elem(functions, index) | first: 0})
      end)

    %{progs | functions: functions, digest: replaced_digest(progs.digest, functions, indexes)}
  end

  defp replaced_digest(nil, _functions, _indexes), do: nil

  defp replaced_digest(digest, functions, indexes) do
    names = indexes |> Enum.sort() |> Enum.map(&elem(functions, &1).name)
    :crypto.hash(:sha256, :erlang.term_to_binary({digest, names}))
  end

  @doc """
  The index of function `name` as FTE's `ED_FindFunction` finds it: a name may follow a
  program number and `:` (`0:name`), the number read as C's `atoi` reads it; this
  program is number 0, so another number finds nothing.
  """
  @spec find_function(t(), String.t()) :: non_neg_integer() | nil
  def find_function(%__MODULE__{} = progs, name) do
    case String.split(name, ":", parts: 2) do
      [number, rest] -> if leading_integer(number) == 0, do: function(progs, rest)
      [_] -> function(progs, name)
    end
  end

  defp leading_integer(text) do
    case Integer.parse(String.trim_leading(text)) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  defp build(data, header, width) do
    <<st_ofs::little-32, st_n::little-32, gd_ofs::little-32, gd_n::little-32, fd_ofs::little-32,
      fd_n::little-32, fn_ofs::little-32, fn_n::little-32, s_ofs::little-32, s_n::little-32,
      g_ofs::little-32, g_n::little-32, entity_fields::little-32>> = header

    strings = binary_part(data, s_ofs, s_n)
    def_size = if width == 16, do: 8, else: 12
    global_defs = defs(binary_part(data, gd_ofs, gd_n * def_size), strings, width)
    functions = functions(binary_part(data, fn_ofs, fn_n * 36), strings)

    %__MODULE__{
      digest: :crypto.hash(:sha256, data),
      statements: statements(binary_part(data, st_ofs, st_n * div(width, 2)), width),
      functions: functions,
      strings: strings,
      texts: texts(strings),
      globals: globals(binary_part(data, g_ofs, g_n * 4), global_defs),
      global_defs: global_defs,
      field_defs: defs(binary_part(data, fd_ofs, fd_n * def_size), strings, width),
      entity_fields: entity_fields,
      function_names:
        functions
        |> Tuple.to_list()
        |> Enum.with_index()
        |> Map.new(fn {f, i} -> {f.name, i} end)
    }
  end

  defp string_at(strings, offset) when offset >= 0 and offset < byte_size(strings) do
    case :binary.match(strings, <<0>>, scope: {offset, byte_size(strings) - offset}) do
      {stop, _} -> binary_part(strings, offset, stop - offset)
      :nomatch -> binary_part(strings, offset, byte_size(strings) - offset)
    end
  end

  defp string_at(_strings, _offset), do: ""

  defp texts(strings) do
    strings
    |> :binary.split(<<0>>, [:global])
    |> Enum.reduce({0, %{}}, fn text, {at, texts} ->
      {at + byte_size(text) + 1, Map.put(texts, at, text)}
    end)
    |> elem(1)
  end

  defp statements(data, 16) do
    for(<<op::little-16, a::little-16, b::little-16, c::little-16 <- data>>,
      do: statement(op, a, b, c, 16)
    )
    |> List.to_tuple()
  end

  defp statements(data, 32) do
    for(<<op::little-32, a::little-32, b::little-32, c::little-32 <- data>>,
      do: statement(op, a, b, c, 32)
    )
    |> List.to_tuple()
  end

  defp statement(op, a, b, c, width) when op in @jump_b, do: {op, a, signed(b, width), c}
  defp statement(61, a, b, c, width), do: {61, signed(a, width), b, c}
  defp statement(104, a, b, c, width), do: {104, a, b, signed(c, width)}
  defp statement(op, a, b, c, _width), do: {op, a, b, c}

  defp signed(value, width) do
    if value >= Bitwise.bsl(1, width - 1), do: value - Bitwise.bsl(1, width), else: value
  end

  defp defs(data, strings, 16) do
    for <<type::little-16, offset::little-16, name::little-32 <- data>>, into: %{} do
      {string_at(strings, name), {def_type(type), offset}}
    end
  end

  defp defs(data, strings, 32) do
    for <<type::little-32, offset::little-32, name::little-32 <- data>>, into: %{} do
      {string_at(strings, name), {def_type(type), offset}}
    end
  end

  defp def_type(type) do
    case Bitwise.band(type, 0x3FFF) do
      known when known < tuple_size(@types) -> elem(@types, known)
      _other -> :void
    end
  end

  defp functions(data, strings) do
    for <<first::little-signed-32, parm_start::little-32, locals::little-32, _profile::little-32,
          name::little-32, _file::little-32, count::little-signed-32, sizes::binary-8 <- data>> do
      %{
        first: first,
        parm_start: parm_start,
        locals: locals,
        name: string_at(strings, name),
        parm_sizes: sizes |> :binary.bin_to_list() |> Enum.take(min(max(count, 0), 8))
      }
    end
    |> List.to_tuple()
  end

  defp globals(data, defs) do
    typed =
      for {_name, {type, offset}} <- defs, reduce: %{} do
        acc ->
          case type do
            :vector ->
              Map.merge(acc, %{offset => :float, (offset + 1) => :float, (offset + 2) => :float})

            :float ->
              Map.put_new(acc, offset, :float)

            other ->
              Map.put_new(acc, offset, other)
          end
      end

    for({word, slot} <- Enum.with_index(for <<word::binary-4 <- data>>, do: word)) do
      decode(word, Map.get(typed, slot))
    end
    |> List.to_tuple()
  end

  defp decode(<<0::32>>, _type), do: 0
  defp decode(<<value::little-float-32>>, :float), do: value
  defp decode(<<value::little-signed-32>>, :float), do: value

  defp decode(<<value::little-signed-32>>, type)
       when type in [:string, :entity, :field, :function, :pointer, :integer], do: value

  defp decode(<<bits::little-32>> = word, _unknown) do
    case {Bitwise.band(Bitwise.bsr(bits, 23), 0xFF), word} do
      {exponent, <<value::little-float-32>>} when exponent != 0 -> value
      {_exponent, <<value::little-signed-32>>} -> value
    end
  end
end
