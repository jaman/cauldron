defmodule QuakeC.Compiler.Ops do
  @moduledoc """
  The quoted Elixir for each QuakeC instruction that computes or moves values: arithmetic
  on floats, vectors and integers, comparisons, loads and stores to globals, entity fields
  and pointers. Jumps, calls, returns and the `state`, `thinktime` and bounds-check
  instructions are `QuakeC.Compiler.Emit`'s.

  An instruction this machine lacks compiles to code raising `QuakeC.Exec.Error` when run.
  """

  alias QuakeC.Compiler.{Emit, Runtime}

  @float_load [24, 26, 27, 28, 29, 126, 153]
  @store [31, 33, 34, 35, 36, 113, 152]
  @store_pointer [37, 39, 40, 41, 42, 127]

  @doc "The statements carrying out instruction `{op, a, b, c}`."
  @spec emit(non_neg_integer(), integer(), integer(), integer(), map()) :: [Macro.t()]
  def emit(1, a, b, c, env), do: w(c, op(:*, num(a, env), num(b, env)), env)
  def emit(2, a, b, c, env), do: dot(a, b, c, env)
  def emit(3, a, b, c, env), do: vscale(b, num(a, env), c, env)
  def emit(4, a, b, c, env), do: vscale(a, num(b, env), c, env)
  def emit(5, a, b, c, env), do: w(c, rt(:divide, [num(a, env), num(b, env)]), env)
  def emit(6, a, b, c, env), do: w(c, op(:+, num(a, env), num(b, env)), env)
  def emit(7, a, b, c, env), do: vpair(:+, a, b, c, env)
  def emit(8, a, b, c, env), do: w(c, op(:-, num(a, env), num(b, env)), env)
  def emit(9, a, b, c, env), do: vpair(:-, a, b, c, env)
  def emit(10, a, b, c, env), do: w(c, bool(op(:==, num(a, env), num(b, env))), env)
  def emit(11, a, b, c, env), do: w(c, bool(op(:==, fvec(a, env), fvec(b, env))), env)
  def emit(12, a, b, c, env), do: w(c, bool(op(:==, text(a, env), text(b, env))), env)

  def emit(op, a, b, c, env) when op in [13, 14],
    do: w(c, bool(op(:==, int(a, env), int(b, env))), env)

  def emit(15, a, b, c, env), do: w(c, bool(op(:!=, num(a, env), num(b, env))), env)
  def emit(16, a, b, c, env), do: w(c, bool(op(:!=, fvec(a, env), fvec(b, env))), env)
  def emit(17, a, b, c, env), do: w(c, bool(op(:!=, text(a, env), text(b, env))), env)

  def emit(op, a, b, c, env) when op in [18, 19],
    do: w(c, bool(op(:!=, int(a, env), int(b, env))), env)

  def emit(20, a, b, c, env), do: w(c, bool(op(:<=, num(a, env), num(b, env))), env)
  def emit(21, a, b, c, env), do: w(c, bool(op(:>=, num(a, env), num(b, env))), env)
  def emit(22, a, b, c, env), do: w(c, bool(op(:<, num(a, env), num(b, env))), env)
  def emit(23, a, b, c, env), do: w(c, bool(op(:>, num(a, env), num(b, env))), env)

  def emit(op, a, b, c, env) when op in @float_load, do: w(c, field(a, b, 0, env), env)

  def emit(25, a, b, c, env) do
    triple(c, env, [
      Emit.convert(:float, field(a, b, 0, env)),
      Emit.convert(:float, field(a, b, 1, env)),
      Emit.convert(:float, field(a, b, 2, env))
    ])
  end

  def emit(30, a, b, c, env) do
    word = op(:+, op(:*, int(a, env), env.size), int(b, env))
    w(c, op(:+, QuakeC.field_base(), op(:*, 4, word)), env)
  end

  def emit(op, a, b, _c, env) when op in @store, do: w(b, r(a, env), env)

  def emit(32, a, b, _c, env),
    do: triple(b, env, [r(a, env), r(a + 1, env), r(a + 2, env)])

  def emit(op, a, b, c, env) when op in @store_pointer,
    do: [set_qc(rt(:store, [qc(), r(b, env), r(c, env), r(a, env)]))]

  def emit(38, a, b, c, env) do
    address = op(:+, rt(:int, [r(b, env)]), op(:*, 4, rt(:int, [r(c, env)])))

    [
      set_qc(
        rt(:store_vector, [qc(), address, {:{}, [], [r(a, env), r(a + 1, env), r(a + 2, env)]}])
      )
    ]
  end

  def emit(44, a, _b, c, env), do: w(c, bool(op(:not, Emit.truth(r(a, env)))), env)

  def emit(45, a, _b, c, env),
    do: w(c, bool(op(:==, fvec(a, env), Macro.escape({0.0, 0.0, 0.0}))), env)

  def emit(46, a, _b, c, env), do: w(c, bool(op(:==, text(a, env), "")), env)
  def emit(op, a, _b, c, env) when op in [47, 48], do: w(c, bool(op(:==, int(a, env), 0)), env)

  def emit(62, a, b, c, env),
    do: w(c, bool(op(:and, Emit.truth(r(a, env)), Emit.truth(r(b, env)))), env)

  def emit(63, a, b, c, env),
    do: w(c, bool(op(:or, Emit.truth(r(a, env)), Emit.truth(r(b, env)))), env)

  def emit(64, a, b, c, env),
    do: w(c, op(:/, bits(:&&&, truncated(num(a, env)), truncated(num(b, env))), 1), env)

  def emit(65, a, b, c, env),
    do: w(c, op(:/, bits(:|||, truncated(num(a, env)), truncated(num(b, env))), 1), env)

  def emit(66, a, b, _c, env), do: w(b, op(:*, num(b, env), num(a, env)), env)
  def emit(67, a, b, _c, env), do: vscale(b, num(a, env), b, env)
  def emit(68, a, b, c, env), do: through(b, c, fn x -> op(:*, x, num(a, env)) end, env)

  def emit(69, a, b, c, env),
    do: through_vector(b, c, fn x -> scale_tuple(x, num(a, env)) end, env)

  def emit(70, a, b, _c, env), do: w(b, rt(:divide, [num(b, env), num(a, env)]), env)
  def emit(71, a, b, c, env), do: through(b, c, fn x -> rt(:divide, [x, num(a, env)]) end, env)
  def emit(72, a, b, _c, env), do: w(b, op(:+, num(b, env), num(a, env)), env)
  def emit(73, a, b, _c, env), do: vpair(:+, b, a, b, env)
  def emit(74, a, b, c, env), do: through(b, c, fn x -> op(:+, x, num(a, env)) end, env)

  def emit(75, a, b, c, env),
    do: through_vector(b, c, fn x -> pair_tuple(:+, x, fvec(a, env)) end, env)

  def emit(76, a, b, _c, env), do: w(b, op(:-, num(b, env), num(a, env)), env)
  def emit(77, a, b, _c, env), do: vpair(:-, b, a, b, env)
  def emit(78, a, b, c, env), do: through(b, c, fn x -> op(:-, x, num(a, env)) end, env)

  def emit(79, a, b, c, env),
    do: through_vector(b, c, fn x -> pair_tuple(:-, x, fvec(a, env)) end, env)

  def emit(88, a, b, _c, env),
    do: w(b, op(:/, bits(:|||, truncated(num(b, env)), truncated(num(a, env))), 1), env)

  def emit(89, a, b, _c, env),
    do:
      through(
        b,
        nil,
        fn x -> op(:/, bits(:|||, truncated(x), truncated(num(a, env))), 1) end,
        env
      )

  def emit(90, a, b, _c, env),
    do: w(b, op(:/, bits(:&&&, truncated(num(b, env)), clear(truncated(num(a, env)))), 1), env)

  def emit(91, a, b, _c, env),
    do:
      through(
        b,
        nil,
        fn x -> op(:/, bits(:&&&, truncated(x), clear(truncated(num(a, env)))), 1) end,
        env
      )

  def emit(92, _a, _b, c, env), do: w(c, rt(:below_one, []), env)
  def emit(93, a, _b, c, env), do: w(c, op(:*, rt(:below_one, []), num(a, env)), env)

  def emit(94, a, b, c, env),
    do:
      w(c, op(:+, num(a, env), op(:*, rt(:below_one, []), op(:-, num(b, env), num(a, env)))), env)

  def emit(95, _a, _b, c, env),
    do: triple(c, env, [rt(:up_to_one, []), rt(:up_to_one, []), rt(:up_to_one, [])])

  def emit(96, a, _b, c, env) do
    triple(c, env, [
      op(:*, rt(:up_to_one, []), float(a, env)),
      op(:*, rt(:up_to_one, []), float(a + 1, env)),
      op(:*, rt(:up_to_one, []), float(a + 2, env))
    ])
  end

  def emit(97, a, b, c, env) do
    triple(
      c,
      env,
      for i <- 0..2 do
        op(
          :+,
          float(a + i, env),
          op(:*, rt(:up_to_one, []), op(:-, float(b + i, env), float(a + i, env)))
        )
      end
    )
  end

  def emit(114, a, b, _c, env), do: w(b, op(:/, int(a, env), 1), env)
  def emit(115, a, b, _c, env), do: w(b, truncated(num(a, env)), env)
  def emit(116, a, b, c, env), do: w(c, rt(:wrap, [op(:+, int(a, env), int(b, env))]), env)
  def emit(117, a, b, c, env), do: w(c, op(:+, num(a, env), int(b, env)), env)
  def emit(118, a, b, c, env), do: w(c, op(:+, int(a, env), num(b, env)), env)
  def emit(119, a, b, c, env), do: w(c, rt(:wrap, [op(:-, int(a, env), int(b, env))]), env)
  def emit(120, a, b, c, env), do: w(c, op(:-, num(a, env), int(b, env)), env)
  def emit(121, a, b, c, env), do: w(c, op(:-, int(a, env), num(b, env)), env)
  def emit(122, a, _b, c, env), do: w(c, op(:/, int(a, env), 1), env)
  def emit(123, a, _b, c, env), do: w(c, truncated(num(a, env)), env)

  def emit(124, a, _b, c, env),
    do: w(c, op(:/, rt(:int, [rt(:load, [qc(), r(a, env), 0])]), 1), env)

  def emit(125, a, _b, c, env),
    do: w(c, truncated(rt(:num, [rt(:load, [qc(), r(a, env), 0])])), env)

  def emit(128, a, b, c, env),
    do: [set_qc(rt(:store, [qc(), r(b, env), r(c, env), op(:/, int(a, env), 1)]))]

  def emit(129, a, b, c, env),
    do: [set_qc(rt(:store, [qc(), r(b, env), r(c, env), truncated(num(a, env))]))]

  def emit(130, a, b, c, env), do: w(c, bits(:&&&, int(a, env), int(b, env)), env)
  def emit(131, a, b, c, env), do: w(c, bits(:|||, int(a, env), int(b, env)), env)
  def emit(132, a, b, c, env), do: w(c, rt(:wrap, [op(:*, int(a, env), int(b, env))]), env)
  def emit(133, a, b, c, env), do: w(c, rt(:int_divide, [int(a, env), int(b, env)]), env)
  def emit(134, a, b, c, env), do: w(c, ibool(op(:==, int(a, env), int(b, env))), env)
  def emit(135, a, b, c, env), do: w(c, ibool(op(:!=, int(a, env), int(b, env))), env)
  def emit(138, a, _b, c, env), do: w(c, ibool(op(:not, set(a, env))), env)

  def emit(139, a, b, c, env),
    do: vscale(a, rt(:divide, [1.0, num(b, env)]), c, env)

  def emit(140, a, b, c, env), do: w(c, bits(:bxor, int(a, env), int(b, env)), env)
  def emit(141, a, b, c, env), do: w(c, bits(:>>>, int(a, env), int(b, env)), env)
  def emit(142, a, b, c, env), do: w(c, rt(:wrap, [bits(:<<<, int(a, env), int(b, env))]), env)
  def emit(143, a, b, c, env), do: w(c, op(:*, 4, op(:+, a, int(b, env))), env)
  def emit(144, a, b, c, env), do: w(c, op(:+, int(a, env), op(:*, 4, int(b, env))), env)

  def emit(146, a, b, c, env) do
    at = op(:+, a, int(b, env))

    triple(c, env, [
      rt(:global, [qc(), at]),
      rt(:global, [qc(), op(:+, at, 1)]),
      rt(:global, [qc(), op(:+, at, 2)])
    ])
  end

  def emit(op, a, b, c, env) when op in 145..151,
    do: w(c, rt(:global, [qc(), op(:+, a, int(b, env))]), env)

  def emit(155, a, b, c, env) do
    at = op(:+, int(a, env), op(:*, 4, int(b, env)))

    triple(c, env, [
      rt(:load_float, [qc(), at]),
      rt(:load_float, [qc(), op(:+, at, 4)]),
      rt(:load_float, [qc(), op(:+, at, 8)])
    ])
  end

  def emit(op, a, b, c, env) when op in 154..160,
    do: w(c, rt(:load, [qc(), r(a, env), r(b, env)]), env)

  def emit(161, a, b, c, env), do: w(c, ibool(op(:<=, int(a, env), int(b, env))), env)
  def emit(162, a, b, c, env), do: w(c, ibool(op(:>=, int(a, env), int(b, env))), env)
  def emit(163, a, b, c, env), do: w(c, ibool(op(:<, int(a, env), int(b, env))), env)
  def emit(164, a, b, c, env), do: w(c, ibool(op(:>, int(a, env), int(b, env))), env)
  def emit(165, a, b, c, env), do: w(c, ibool(op(:<=, int(a, env), num(b, env))), env)
  def emit(166, a, b, c, env), do: w(c, ibool(op(:>=, int(a, env), num(b, env))), env)
  def emit(167, a, b, c, env), do: w(c, ibool(op(:<, int(a, env), num(b, env))), env)
  def emit(168, a, b, c, env), do: w(c, ibool(op(:>, int(a, env), num(b, env))), env)
  def emit(169, a, b, c, env), do: w(c, ibool(op(:<=, num(a, env), int(b, env))), env)
  def emit(170, a, b, c, env), do: w(c, ibool(op(:>=, num(a, env), int(b, env))), env)
  def emit(171, a, b, c, env), do: w(c, ibool(op(:<, num(a, env), int(b, env))), env)
  def emit(172, a, b, c, env), do: w(c, ibool(op(:>, num(a, env), int(b, env))), env)
  def emit(173, a, b, c, env), do: w(c, ibool(op(:==, int(a, env), num(b, env))), env)
  def emit(174, a, b, c, env), do: w(c, ibool(op(:==, num(a, env), int(b, env))), env)

  def emit(175, a, b, c, env),
    do: w(c, rt(:string_offset, [r(a, env), truncated(num(b, env))]), env)

  def emit(176, a, b, c, env), do: w(c, rt(:string_distance, [r(a, env), r(b, env)]), env)
  def emit(178, a, b, c, env), do: w(c, rt(:string_at, [qc(), r(a, env), num(b, env)]), env)
  def emit(179, a, b, c, env), do: w(c, op(:*, int(a, env), num(b, env)), env)
  def emit(180, a, b, c, env), do: w(c, op(:*, num(a, env), int(b, env)), env)
  def emit(181, a, b, c, env), do: vscale(a, int(b, env), c, env)
  def emit(182, a, b, c, env), do: vscale(b, int(a, env), c, env)
  def emit(183, a, b, c, env), do: w(c, rt(:divide, [int(a, env), num(b, env)]), env)
  def emit(184, a, b, c, env), do: w(c, rt(:divide, [num(a, env), int(b, env)]), env)
  def emit(185, a, b, c, env), do: w(c, bits(:&&&, int(a, env), truncated(num(b, env))), env)
  def emit(186, a, b, c, env), do: w(c, bits(:|||, int(a, env), truncated(num(b, env))), env)
  def emit(187, a, b, c, env), do: w(c, bits(:&&&, truncated(num(a, env)), int(b, env)), env)
  def emit(188, a, b, c, env), do: w(c, bits(:|||, truncated(num(a, env)), int(b, env)), env)
  def emit(189, a, b, c, env), do: w(c, ibool(op(:and, set(a, env), set(b, env))), env)
  def emit(190, a, b, c, env), do: w(c, ibool(op(:or, set(a, env), set(b, env))), env)

  def emit(191, a, b, c, env),
    do: w(c, ibool(op(:and, set(a, env), op(:!=, num(b, env), 0))), env)

  def emit(192, a, b, c, env), do: w(c, ibool(op(:or, set(a, env), op(:!=, num(b, env), 0))), env)

  def emit(193, a, b, c, env),
    do: w(c, ibool(op(:and, op(:!=, num(a, env), 0), set(b, env))), env)

  def emit(194, a, b, c, env), do: w(c, ibool(op(:or, op(:!=, num(a, env), 0), set(b, env))), env)
  def emit(195, a, b, c, env), do: w(c, ibool(op(:!=, int(a, env), num(b, env))), env)
  def emit(196, a, b, c, env), do: w(c, ibool(op(:!=, num(a, env), int(b, env))), env)

  def emit(219, a, b, c, env) do
    address = rt(:field_address, [qc(), r(a, env), r(b, env)])

    [
      set_qc(
        rt(:store_vector, [qc(), address, {:{}, [], [r(c, env), r(c + 1, env), r(c + 2, env)]}])
      )
    ]
  end

  def emit(op, a, b, c, env) when op in 220..222,
    do: [
      set_qc(rt(:store, [qc(), rt(:field_address, [qc(), r(a, env), r(b, env)]), 0, r(c, env)]))
    ]

  def emit(246, a, b, _c, env), do: w(b, r(a, env), env) ++ w(b + 1, r(a + 1, env), env)

  def emit(op, _a, _b, _c, _env) do
    message = "unknown opcode #{op}"
    [quote(generated: true, do: raise(QuakeC.Exec.Error, unquote(message)))]
  end

  defp r(slot, env), do: Emit.read(slot, env)
  defp w(slot, value, env), do: [Emit.write(slot, value, env)]
  defp qc, do: Emit.qc()
  defp set_qc(value), do: {:=, [generated: true], [Emit.qc(), value]}

  defp rt(fun, args), do: {{:., [], [Runtime, fun]}, [generated: true], args}
  defp op(operator, left, right), do: {operator, [generated: true], [left, right]}
  defp op(:not, value), do: {:not, [generated: true], [value]}

  defp bits(operator, left, right),
    do: {{:., [], [Bitwise, operator]}, [generated: true], [left, right]}

  defp clear(value), do: {{:., [], [Bitwise, :bnot]}, [generated: true], [value]}
  defp truncated(value), do: {{:., [], [Kernel, :trunc]}, [generated: true], [value]}

  defp num(slot, env), do: Emit.convert(:num, r(slot, env))
  defp int(slot, env), do: Emit.convert(:int, r(slot, env))
  defp float(slot, env), do: Emit.convert(:float, r(slot, env))
  defp text(slot, env), do: rt(:text, [qc(), r(slot, env)])
  defp bool(value), do: Emit.bool(value)
  defp ibool(value), do: Emit.ibool(value)

  defp field(entity, field, extra, env) do
    word = op(:+, op(:*, int(entity, env), env.size), plus(int(field, env), extra))
    QuakeC.Memory.get_code(Emit.space(:fields), word)
  end

  defp plus(value, 0), do: value
  defp plus(value, extra) when is_integer(value), do: value + extra
  defp plus(value, extra), do: op(:+, value, extra)

  defp set(slot, env) do
    value = r(slot, env)

    quote generated: true do
      case unquote(value) do
        value when is_binary(value) -> true
        value when is_number(value) -> value != 0
        _ -> false
      end
    end
  end

  defp fvec(slot, env),
    do: {:{}, [], [float(slot, env), float(slot + 1, env), float(slot + 2, env)]}

  defp triple(slot, env, [x, y, z]) do
    [
      quote(generated: true, do: {x, y, z} = {unquote(x), unquote(y), unquote(z)})
      | w(slot, quote(generated: true, do: x), env) ++
          w(slot + 1, quote(generated: true, do: y), env) ++
          w(slot + 2, quote(generated: true, do: z), env)
    ]
  end

  defp dot(a, b, c, env) do
    sum =
      op(
        :+,
        op(
          :+,
          op(:*, float(a, env), float(b, env)),
          op(:*, float(a + 1, env), float(b + 1, env))
        ),
        op(:*, float(a + 2, env), float(b + 2, env))
      )

    w(c, sum, env)
  end

  defp vscale(from, factor, to, env) do
    [
      quote(generated: true, do: k = unquote(factor))
      | triple(
          to,
          env,
          for(i <- 0..2, do: op(:*, float(from + i, env), quote(generated: true, do: k)))
        )
    ]
  end

  defp vpair(operator, a, b, c, env),
    do: triple(c, env, for(i <- 0..2, do: op(operator, float(a + i, env), float(b + i, env))))

  defp scale_tuple(tuple, factor) do
    quote generated: true do
      {px, py, pz} = unquote(tuple)
      k = unquote(factor)
      {px * k, py * k, pz * k}
    end
  end

  defp pair_tuple(operator, tuple, other) do
    quote generated: true do
      {px, py, pz} = unquote(tuple)
      {ox, oy, oz} = unquote(other)

      {unquote(op(operator, quote(generated: true, do: px), quote(generated: true, do: ox))),
       unquote(op(operator, quote(generated: true, do: py), quote(generated: true, do: oy))),
       unquote(op(operator, quote(generated: true, do: pz), quote(generated: true, do: oz)))}
    end
  end

  defp through(address, result, change, env) do
    changed = change.(quote(generated: true, do: current))
    fun = quote(generated: true, do: fn current -> unquote(changed) end)

    run =
      {:=, [generated: true],
       [
         {quote(generated: true, do: value), Emit.qc()},
         rt(:through, [qc(), r(address, env), fun])
       ]}

    case result do
      nil -> [run]
      slot -> [run | w(slot, quote(generated: true, do: value), env)]
    end
  end

  defp through_vector(address, result, change, env) do
    changed = change.(quote(generated: true, do: current))
    fun = quote(generated: true, do: fn current -> unquote(changed) end)

    [
      {:=, [generated: true],
       [
         {quote(generated: true, do: {x, y, z}), Emit.qc()},
         rt(:through_vector, [qc(), r(address, env), fun])
       ]}
      | w(result, quote(generated: true, do: x), env) ++
          w(result + 1, quote(generated: true, do: y), env) ++
          w(result + 2, quote(generated: true, do: z), env)
    ]
  end
end
