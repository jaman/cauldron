# QuakeC

A QuakeC virtual machine in Elixir. It reads compiled QuakeC programs (`progs.dat`,
`csprogs.dat`, `menu.dat`) and runs their functions against builtins the host supplies.

## Installation

```elixir
def deps do
  [
    {:quake_c, "~> 0.2"}
  ]
end
```

```elixir
{:ok, progs} = QuakeC.Progs.parse(File.read!("progs.dat"))
host = %{qc: QuakeC.new(progs)}
host = QuakeC.Exec.call_named(host, "main", MyGame.Builtins)
```

* `QuakeC.Progs` reads id's version 6 programs and FTE's version 7 programs, with 16- or
  32-bit statements.
* `QuakeC` is the program's memory: globals, every entity's fields, and a heap for
  `memalloc`. A pointer is a byte address into one of the three. The memory is written
  in place, as a QuakeC machine's is: every copy of the `QuakeC` struct sees every
  write. It belongs to the process that made it, and `QuakeC.release/1` frees it.
* `QuakeC.Exec` runs functions: Quake's instructions and FTE's extended set (integers,
  pointers and arrays, switch and case, hexen2-style calls, random numbers, field
  stores), with a statement budget per call and an optional trace of the functions
  entered.
* `QuakeC.Compiler` turns a program into Elixir modules the first time it runs: each
  QuakeC function a function, each basic block a function its jumps call. Generated
  modules are compiled in parallel and cached on disk by the program's digest.

The host is any map with the memory under `:qc`. Builtins are a module with
`call(host, builtin, argument_count)`, where `builtin` is the builtin's number, or its name
for builtins a program binds by name (`#0:name`).

## How programs are compiled

A program is compiled to Elixir modules the first time it runs and loaded from a cache
on every run after: the cache is the application setting `:quake_c, :cache_dir`, by
default the user cache directory's `quake_c`, and a program's entry in it is named by its
digest. Compiling a program of 90 000 statements takes about half a minute, once.

## Where it came from

The opcode meanings are fixed by the program format. The interpreter, memory and
loader were written for this package against that format; FTE's `pr_comp.h` and
`execloop.h` were read for the meaning of FTE's extended instructions.

## License

MIT.
