# Contributing

This chapter is for someone working on the engine itself: the commands to run, the rules
a change is held to, and how a release is made.

## The repository

`cauldron/` is one git repository holding a family of Mix projects, one per directory.
Each is an ordinary project you can `cd` into and work in on its own. `cauldron_examples/`
holds complete games and apps used to exercise the packages; it is not published.
`book/` holds this document.

```
cauldron/
├── cauldron_core/          Cauldron.*            worlds, input, sound, saving, net
├── cauldron_2d/            Cauldron2D.*          tiles, atlases, drawing
├── cauldron_2d_drafter/    Cauldron2D.Drafter.*  terminal + SSH front end
├── cauldron_2d_net/        Cauldron2D.Net.*      browser front end
├── cauldron_2d_wx/         Cauldron2D.Wx.*       desktop window front end
├── cauldron_2d_native/     Cauldron2D.Native.*   phone front end
├── cauldron_net/           Cauldron.Net.*        worlds across a socket
├── cauldron_3d/            Cauldron3D.*          software 3D renderer
├── cauldron_3d_scene/      Cauldron3D.Scene.*    a 3D scene as data
├── cauldron_3d_formats/    Cauldron3D.Formats.*  Quake, glTF, VRM
├── cauldron_3d_net/        Cauldron3D.Net.*      a 3D scene in a browser
├── cauldron_3d_kino/       Cauldron3D.Kino.*     a 3D scene in Livebook
├── cauldron_gpu/           CauldronGPU.*         Metal and Vulkan
├── cauldron_native/        CauldronNative.*      iOS and Android hosts
├── cauldron_2d_easel*/     Cauldron2D.Easel.*   art editing
├── cauldron_sfx*/          Cauldron.SFX.*        sound-effect editing
├── linocut/                Linocut.*             pictures as code
├── quake_c/                QuakeC.*              a QuakeC virtual machine
└── book/                   this document
```

A sibling dependency is declared through `family/4` in the project's `mix.exs`: the path
is used while `PLUMB_HEX` is unset and the directory exists, and the Hex requirement is
used otherwise. That is what lets every package build from a checkout and from Hex.

## The commands

In any package:

```sh
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test
mix docs
```

All six are expected to pass before a change is committed. `warnings_as_errors` is set in
every package, so `mix compile` and `mix docs` already refuse a warning.

Across the whole repository:

```sh
for p in */; do [ -f "$p/mix.exs" ] && (cd "$p" && mix format --check-formatted && mix credo --strict && mix test); done
elixir book/build.exs
```

`book/build.exs` assembles `book/build/cauldron.md` from the chapters and, when Pandoc is
installed, `book/build/cauldron.html`.

## The rules a change is held to

- **No warnings.** A warning fails the build in every package.
- **Every public module is documented.** `@moduledoc false` marks internals; a module
  with neither a doc nor a `false` is a mistake.
- **Guides are for users.** A guide explains how to use a package: what it does, how to
  call it, what to watch for. It does not narrate how the code got there — no release
  notes, no "this used to", no account of a bug fixed on the way. History lives in
  `CHANGELOG.md`; design reasoning lives in this book.
- **Changelogs are versioned.** `CHANGELOG.md` gets a `## [Unreleased]` section for work
  in progress, turned into `## [x.y.z]` at release.
- **A package ships what it needs at run time.** If a file is read by the package, it
  belongs in `package.files`; build output belongs in `.gitignore`.
- **Core does not draw.** Nothing in `cauldron_core` may depend on a way of drawing.

## Documentation

Each package's `mix.exs` lists its guides in `docs/0`:

```elixir
docs: [
  main: "readme",
  extras: ["README.md", "guides/terminal.md", "guides/serving.md", "CHANGELOG.md"],
  groups_for_extras: [Guide: ["guides/terminal.md", "guides/serving.md"]]
]
```

A guide is only published when it is in `extras`; a file linked from a guide but not in
`extras` produces an ExDoc warning. `mix docs` must build with no warnings.

The book is separate from package documentation. It is for reading end to end:

- **Part one — using Cauldron** — the package guides, in reading order, starting with the
  introduction and installation.
- **Part two — working on Cauldron** — architecture, extending, and this chapter.

The contents and the order are declared in `book/contents.exs`; `book/build.exs` reads
it. Adding a chapter means adding a file and an entry there.

## Testing notes

- `drafter`'s pseudoterminal tests and `cauldron_core`'s ledger test need a real
  environment: `Pty.spawn/2` must be able to allocate a terminal, and `ps` must be able
  to see the current process. In a restricted container or sandbox those tests fail with
  `"Operation not permitted"` rather than a real assertion; run them on a normal machine.
- Tests use `@tag :tmp_dir` or `System.tmp_dir!()` with `on_exit/1` for files; a test
  that leaves files behind is a bug.
- `cauldron_3d_scene` and `cauldron_gpu` have no tests yet. A change there is verified by
  hand for now; adding a headless test for the software renderer is welcome.

## Releasing

Releases go through plumb from the directory above the repositories:

```sh
cd ..
./publish cauldron drafter french_curve tuning_fork --dry-run
./publish cauldron drafter french_curve tuning_fork
```

`--dry-run` runs every check and prints the plan without writing. A release needs:

- a clean working tree in each repository;
- every package at the same version within a repository;
- `mix format --check-formatted`, `mix test` and `mix docs` passing in every package;
- the README's install snippet matching the version being released;
- `mix hex.build` producing a package that ships no file git does not track.

plumb bumps the version, rewrites the sibling requirements, commits `Release vX.Y.Z`,
tags, pushes, and publishes the packages dependencies first.

## Licensing

The `cauldron_*` packages are AGPL-3.0-only, with a commercial option for closed use
described in `COMMERCIAL.md`. `linocut`, `quake_c` and `drafter` are MIT, as are
`french_curve`, `tuning_fork` and `gamepad` in their own repositories. A change is
contributed under the terms of the package it lands in; do not copy code in that cannot be
licensed that way.
