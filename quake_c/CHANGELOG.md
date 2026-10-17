# Changelog

## [0.3.3]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.2]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.1]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.0]

### Changed

- The README is rewritten in plain sentences.

## [0.2.0]

### Added

- `QuakeC.Progs` reads id's version 6 programs and FTE's version 7 programs with 16- and
  32-bit statements, keeps every string of the table by its offset (`texts`) and carries
  the program's `digest`.
- `QuakeC.Progs.find_function/2`, FTE's `ED_FindFunction`: a name may follow a program
  number and `:`.
- `QuakeC.Progs.replace/2`: named program functions run by the host in place of their
  QuakeC bodies, as builtins bound by name; the digest names the replacements.
- `QuakeC` memory with byte-address pointers into globals, entity fields and an
  allocating heap (`alloc/2`, `free/2`, `load/2`, `store/3`), written in place: every
  copy of the struct sees every write, and it belongs to the process that made it.
  `QuakeC.move/4` and `QuakeC.fill/4` copy and fill memory by words, for `memcpy` and
  `memset`; `QuakeC.copy/1`, `QuakeC.release/1`, `QuakeC.update_slot/3`.
- `QuakeC.Exec` runs Quake's instructions and FTE's extended instructions, with builtins
  by number or by name, a statement budget and an optional function trace.
- `QuakeC.Exec.call/4` option `:before`: a function of the host run before each call,
  which a host uses to bring its `autocvar_` globals up to date.
- `QuakeC.Exec.abort/1`: a builtin stops every running function, as FTE's
  `AbortStack`; the outermost `QuakeC.Exec.call/4` returns the host as it stands.
- `QuakeC.Compiler`: programs run as generated Elixir modules, compiled in parallel and
  cached on disk by the program's digest. Compiled calls pass arguments and return
  values as values; the parameter and return slots are written for builtins and calls
  from the host.
