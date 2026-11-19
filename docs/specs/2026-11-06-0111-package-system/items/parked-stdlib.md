# Parked — core-library areas deliberately out of reach

"Full functional match as much as logically possible" — these are the
honest bounds. Each says why it doesn't map or doesn't pay yet. None
is permanently banned; several graduate when the language grows the
machinery they need.

## Needs reflection / `any` runtime values — the language lacks it

**Un-parked → milestone R**
(`docs/specs/2026-11-11-type-descriptors/`): compiler-emitted type
descriptors landed the machinery these packages waited on; R6 closed
the milestone out. Returned under R2–R6: `fmt` `%v`, `reflect` lite,
`encoding/gob`, `encoding/xml`, `text/template`, and `database/sql`'s
`scan[T]` half. Staying parked: `html/template` (out of R's scope)
and `database/sql`'s driver-registry half (R6 shipped the lite scan
only — trigger: a second driver or `Scan(any)` consumer).

**Re-measured at R6 closeout** — the remaining descriptor-gated items,
each with its own trigger rather than a blanket wait on reflection:

- `runtime/pprof` — descriptors cover the type side, but a profiler
  needs task/stack introspection the runtime doesn't expose. Trigger:
  a real profiling consumer files the runtime-side surface it needs.
- Plugin loading — needs dynamic symbol lookup + ABI descriptors
  across a process boundary, not just type metadata. Trigger: an
  embedding host that needs runtime-loaded modules.

- `html/template` — string-keyed `map[string]any` pipelines; out of
  milestone R's scope (its `text/template` sibling landed).
- `database/sql` driver-registry + `Scan(any)` — R6's `scan[T]`
  covers the descriptor half; the registry half waits on a second
  driver or a heterogeneous-column consumer.

## Needs machinery the language doesn't have

- Plugin loading and `runtime/pprof` — descriptor-gated, recorded
  with their own triggers in the R6 re-measure above.
- Compiler-self packages (ast/parser/token class),
  `runtime` internals — runtime/codecs introspection doesn't exist.
- `unsafe` in the memory-unsafe sense — oxl `unsafe` is a
  scoping-block marker that silences no checks (`docs/semantics/
  ownership.md`), not `Pointer` arithmetic.

## Replaced by language semantics — porting them would be wrong

- `context` — `scope` blocks + structured cancellation already carry
  cancellation + deadline semantics; a package would double the
  mechanism. `sync.Cond`-style waits live in `std/sync`.
- `testing.T` beyond what `std/testing` has — benchmarks/fuzzing are
  possible later but not a parity blocker.
- `os/exec`, `os/signal` — process/signal surface exists in `rt.c`
  but is runtime-owned; a thin `std/os` growth covers what's needed
  without a process-exec API.

## Doesn't pay at this scale

- `image`, `image/color`, `image/draw` — needs a real use case first
  (the GUI pilot goes through GTK, not an image buffer).
- `compress/{gzip,zlib,flate}`, `archive/{tar,zip}` — C-FFI wrap is
  trivial when needed; pure-.oxl ports wait for `[]byte` to settle.
- `net/http/httputil`, `pprof`, `net/url` (small — folds into
  `std/net/http` when it needs it), `mime`, `net/mail`.
- `container/{heap,list,ring}` — `std/collections` covers the map/set
  core; heap/ring are addable on demand.
- `log/slog`, `slog` — `std/log` ships first; structured logging
  rides on it later.
- `time/tzdata`, `syscall` — platform machinery deferred until a
  real consumer exists.

## Parked pending runtime type descriptors

**Un-parked → milestone R** (`docs/specs/2026-11-11-type-descriptors/`).

- `fmt %v` (issue #28) — a generic default-format verb needs runtime
  reflection over the value's type; `err` codes, `own` graph nodes,
  and struct fields carry no type descriptors at runtime, so `%v`
  cannot discover what it would print. The explicit verbs (`%d`,
  `%s`, `%f`, `%q`…) stay the contract until rt carries type
  metadata; re-open when descriptors land.
- `errors.As` (issue #27, partial) — the cause chain (`wrap`,
  `unwrap`, `is`) is live, but `as` binds a *typed* target and err is
  an int64 code with no type identity to match against. Same
  descriptor gap as `%v` — both unblock together.
