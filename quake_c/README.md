# QuakeC

QuakeC is a QuakeC virtual machine in Elixir. It reads compiled QuakeC programs
(`progs.dat`, `csprogs.dat`, `menu.dat`). It runs their functions against builtins that
your host supplies.

## Where it fits

`quake_c` knows nothing of worlds, drawing or networking. The host does that work. A 3D
host reads the game's files and maps with
[`cauldron_3d_formats`](https://hexdocs.pm/cauldron_3d_formats). It answers the
program's tracing and movement builtins with [`cauldron_3d`](https://hexdocs.pm/cauldron_3d)'s
`Cauldron3D.Hull` and `Cauldron3D.Move`. It draws with `cauldron_3d` or
[`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu).

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:quake_c, "~> 0.3"}
  ]
end
```

## Usage

```elixir
defmodule MyGame.Builtins do
  def call(%{qc: qc} = host, 25, _argument_count) do
    IO.write(QuakeC.string(qc, QuakeC.slot(qc, 4)))
    host
  end
end

{:ok, progs} = QuakeC.Progs.parse(File.read!("progs.dat"))
host = %{qc: QuakeC.new(progs)}
host = QuakeC.Exec.call_named(host, "main", MyGame.Builtins)
```

The host is any map with the memory under `:qc`.

Write the builtins as a module with `call(host, builtin, argument_count)`. It returns the
host. `builtin` is the builtin's number. For a builtin the program binds by name
(`#0:name`), it is the name.

A builtin's arguments are in global slots 4, 7, 10 and on, three slots each. Read them
with `QuakeC.slot/2` or `QuakeC.slot_vector/2`. Put the result in slots 1 to 3 with
`QuakeC.put_slot/3`. A builtin may run QuakeC itself by calling `QuakeC.Exec.call/4`
again. It may stop every running function with `QuakeC.Exec.abort/1`.

## What is here

* `QuakeC.Progs` reads id's version 6 programs and FTE's version 7 programs. It reads
  16-bit and 32-bit statements. `function/2` finds a function by name.
* `QuakeC` holds the program's memory. Read and write globals with `global/2` and
  `put_global/3`. Read and write entity fields with `field/3` and `put_field/4`. Allocate
  heap memory for `memalloc` with `alloc/2` and `free/2`.
* A pointer is a byte address into the globals, the fields or the heap.
* The memory is written in place, as a QuakeC machine's is. Every copy of the `QuakeC`
  struct sees every write. `QuakeC.copy/1` makes a copy that is written apart.
* The memory belongs to the process that made it. `QuakeC.release/1` frees it.
* `QuakeC.Exec` runs functions with `call/4` and `call_named/4`. It runs Quake's
  instructions and FTE's extended set. The extended set adds integers, pointers and
  arrays, switch and case, hexen2-style calls, random numbers and field stores.
* `QuakeC.Exec` takes options. `:budget` limits the statements one call may run.
  `:trace` gets the name of every function entered. `:before` runs on the host before
  each call.
* A runaway loop, a null function or an unknown builtin raises `QuakeC.Exec.Error`.
* `QuakeC.Compiler` turns a program into Elixir modules the first time it runs. Each
  QuakeC function becomes a function. Each basic block becomes a function that its jumps
  call. The modules are compiled in parallel and cached on disk.

## The compile cache

A program is compiled the first time it runs on a node. Every later run loads it from
the cache. The first run of a large program takes noticeable time.

The cache directory is the application setting `:quake_c, :cache_dir`. By default it is
the user cache directory's `quake_c`. Each program's entry is named by its digest.

```elixir
config :quake_c, cache_dir: "/var/cache/my_game/quake_c"
```

## License

MIT. FTE's `pr_comp.h` and `execloop.h` define the extended instructions this machine
runs.
