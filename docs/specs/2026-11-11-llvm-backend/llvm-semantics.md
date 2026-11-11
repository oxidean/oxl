# llvm-semantics.md — oxl→LLVM IR representation + ABI contract

The load-bearing contract for milestone L. It pins what emitted LLVM
IR *means*: every representation choice a reader can observe, the ABI
the emitted module owes `runtime/rt.c`, and every place the LLVM lane
deliberately diverges from the C lane's emitted shape. The model spec
is `docs/specs/2026-11-10-web-target/js-semantics.md`; the native ABI
baseline is `docs/semantics/interfaces.md` §Runtime ABI plus `runtime/
rt.h`.

Two layout domains with different rules:

- **Boundary types are matched field-for-field.** Anything `rt.h`
  declares (`OxlStr`, `RtSlice`, `RtFnv`, `RtIface`, `RtFrame`,
  `RtDefer`, and every `rt_*` signature) is emitted as an IR type with
  the same fields in the same order at explicit widths — clang then
  computes the same layout for the `.ll` module and for `rt.c` under
  the same triple. No guessing at C layout: identical field lists at
  identical widths on identical datalayout is the whole argument.
- **Lane-owned types are self-consistent.** `%o_s_*`, `%o_en_*`,
  `%o_ret_*`, `%o_frm_*` (past the `RtFrame` header), `%o_env_*`,
  vtab arrays: no C code ever sees their layout, so the lane picks
  the simplest self-consistent form — noted per type below.

## 1. Type representation

| oxl type | IR type | notes |
|---|---|---|
| `int` / `err` | `i64` | wrap-on-overflow: `add`/`sub`/`mul` (plain, no nsw/nuw — C lane's unsigned-wrap semantics preserved); `sdiv`/`srem`; bitwise ops map to IR `and`/`or`/`xor` |
| `byte` | `i8` | masked ops like the C lane's `uint8_t` |
| `float` | `double` | identical IEEE-754 |
| `bool` | `i32` | C `int` at every boundary (rt.h never takes bool, but struct fields and ret structs are C-shaped in the C lane; `i32` keeps the lane honest at extern edges) |
| `str` | `%OxlStr = type { ptr, i64 }` | boundary — field-for-field `rt.h` |
| `cstr` | `ptr` | NUL-terminated, extern-boundary only |
| `[]T` | `%RtSlice = type { ptr, i64, i64, i64 }` | boundary — `{ptr,len,cap,heap}`, element type erased exactly like the C lane |
| `struct` | `%o_s_<qn> = type { f0, f1, … }` | source field order, `f_<name>` order preserved; lane-owned layout |
| `enum` | `%o_en_<qn> = type { i32, [4 x i8], <payloadTy> }` | lane-owned — §4 |
| `own T` / `ref T` / `mut T` | `ptr` | opaque pointers; borrow/move checks are rt.c calls, not types |
| `chan` / `chan own T` | `ptr` | `RtChan*` opaque |
| `shared` | `ptr` | `RtShared*` opaque |
| `scope` handle | `ptr` | `RtScope*` opaque — never dereferenced in emitted code |
| `RtScope` storage | dynamic-size `i8` region | §5 — the emitted IR never declares `RtScope`'s layout |
| fn value | `%RtFnv = type { ptr, ptr }` | `{env, fp}` boundary pair |
| iface | `%RtIface = type { ptr, ptr }` | `{data, vtab}` boundary pair |
| `[v, err]` ret | `%o_ret_<fn> = type { <val>, i64 }` | lane-owned; extern pair-rets degrade to `i64` like the C lane |
| susp frame | `%o_frm_<fn> = type { ptr, i32, ptr, ptr, … }` | `RtFrame` header is boundary; tail is lane-owned — §5 |
| `void` | `void` | |
| `nil` | `ptr null` / zeroed aggregate | per type |

`main` entry is unchanged: rt.c's `main()` calls `oxl_main()` — the
lane emits `define void @oxl_main()` containing global-init stmts
then either `call void @o_f_main()` (non-susp) or the
`rt_task_new` + `rt_run_root` root-frame drive (susp).

### The explicit-width firewall

`rt.h` spells `int64_t`/`uint8_t`/`int`/`double`/pointers. The IR
maps are `i64`/`i8`/`i32`/`double`/`ptr` — every boundary field is
explicit-width, so layout equivalence survives any triple clang is
invoked with: clang computes both sides' layouts under the same
datalayout. `int` maps to `i32` unconditionally (every supported
target has 32-bit `int`); `size_t`/`ssize_t`/`long` never appear in
the emitted call surface (rt.h's public fns use `int64_t` for sizes —
`rt_task_new(poll, int64_t bytes)` included). Pointer-sized values
(chan elements, `own void`, `RtFnv` halves) are `ptr` — width
follows the triple automatically.

## 2. Emit shape

`emit_llvm(r, testm) -> str` returns one module text:

```llvm
; out.ll — emitted by oxl --target llvm
%OxlStr = type { ptr, i64 }
%RtSlice = type { ptr, i64, i64, i64 }
%RtFnv = type { ptr, ptr }
%RtIface = type { ptr, ptr }
%o_s_main_Point = type { i64, i64 }
declare ptr @rt_alloc(i64)
define i64 @o_f_main_hypot2(i64 %x, i64 %y) { … }
define void @oxl_main() { … }
```

- **No `target triple`/`target datalayout` lines.** clang supplies
  both from `-target` at compile time; emitting a triple would
  override `--triple` passthrough. The module is triple-neutral
  text — the size model (§6) is the only place a pointer width is
  assumed, and it assumes 8 with over-reservation being safe.
- **Symbols keep the C lane's names.** `o_f_`, `o_s_`, `o_en_`,
  `o_ret_`, `o_vret_`, `o_frm_`, `o_poll_`, `o_g_`, `o_cl_`,
  `o_env_` (closure env structs), `o_denv_`, `o_def_` (defer
  thunks), `o_vt_`, `o_drop_`, `l_tr_`-band spawn thunks over
  `o_args_` structs, `oxl_main`. The `o_*` scheme is what
  G1 registers as defs; spelled under `@`/`%` the token scan
  (`gscan`'s `[A-Za-z_][A-Za-z0-9_]*` walk) picks them up
  identically — `@o_f_main` yields token `o_f_main`. Extern names
  stay bare (`declare i64 @rt_open_read(%OxlStr)`), call sites spell
  `@rt_open_read` — the same bare-name edge the C lane relies on.
- **G1 reachability is reused verbatim** — same `gubegin`/`gudrain`/
  `gdef`/`gscan` calls, same unit model (one def set + emitted text
  per decl). Dead `declare`s drop the same way dead C protos drop.
  False-positive edges (identifier tokens inside `c"…"` string data,
  `;` comments) are conservative-safe exactly as in C.
- **SSA discipline**: named `%v<n>` registers and `L<n>`/`s<n>`
  block labels from lane counters — never numbered regs (text emit
  can't keep a global ordinal honest across buffer joins), never
  `o_*`-prefixed (a `%v3` token can never collide with a defined
  symbol). Entry-block `alloca`s for locals + by-value aggregate
  slots; mem2reg promotes what it can — the lane emits
  `alloca`/`load`/`store` mechanically rather than tracking
  SSA values itself. Match-in-expression and struct literals get a
  result `alloca` + arm stores + load — the same shape the C lane's
  `({…})` statement expressions produce, no GNU extension needed.
- **`;` comments** are legal in `.ll` — the lane emits a module
  banner + per-decl `; o_f_<qn>` markers. The G1 scanner can't tell
  comment tokens from code tokens, so a marker only ever spells the
  enclosing unit's own def (a self-edge is harmless); comments
  otherwise carry no `o_*`/extern names.
- testm=1 emits the same `test_*` wrapper pattern: one
  dynamic-size scope `alloca` + `rt_scope_try` + trap-print per test,
  mirroring codegen.oxl's scope-wrapped runner.

## 3. Calls, fns, globals

- `o_f_<qn>` — `define <ret> @o_f_<qn>(<params>)`; receiver lowers to
  a leading param exactly like `gparams2` spells it. Pair returns use
  the fn's `%o_ret_<qn>` type by value.
- Calls are `call <ret> @<callee>(args)` — direct everywhere; fn
  values go through `%RtFnv`'s `fp` slot loaded + `call … %fp(ptr %env,
  args…)` — the callee is a `ptr` value carrying the call's
  signature —, the same uniform
  indirect-call shape `RtFnv` fixes.
- Iface calls load `vtab[i]` from the `%RtIface`'s `vtab` ptr and
  `call … %slot(ptr %data, args…)` — `o_vt_<w>_<key>` tables are
  `@o_vt_<w>_<key> = constant [N x ptr] [ptr @<thunk0>, …]`; the
  `RtIface.vtab` field (a `ptr`) takes the array's address. Method
  thunk signatures stay `(ptr data, args…)` — any impl slots in.
- Generic instantiations are the same monomorphized `o_f_<mangled>`
  copies via the shared `ginst_name`/`ginst_queue` machinery; susp
  insts emit only frames (no `o_f_` proto) like the C lane.
- Globals: `@o_g_<qn> = global <ty> zeroinitializer`, initialized by
  `ginit` stmts inside `@oxl_main` — identical ordering discipline
  to the C lane's `@@GLOBALS@@` splice (the same G1 unit ordering
  constraint applies; the splice marker mechanics are per-lane but
  the semantic is shared).
- Externs: `declare` per used extern (G1-dropped when unused),
  spelled with the `gcty`-mapped signature; `[T, err]` extern rets
  degrade to `i64` exactly like `gret_c(is_oxl=false)`.
- `cl` closures: `%o_env_<fn>` env struct + `o_cl_<id>`
  (`define` taking `(ptr env, …)` + a captured-env alloca/copy —
  same copy-capture semantics; `RtFnv` pairs `{env, fp}` emitted as
  the constant pair or a computed pair where env is dynamic).
- Defer thunks `o_def_*` and drop helpers `o_drop_*` keep their C
  signatures; `RtDefer` marks/drains stay `rt_defer_*` calls.

## 4. Structs, enums, unions, ret structs

- `%o_s_<qn>` fields emit in source order at §1 widths; `f_<name>`
  index order is field order. GEP indices are compile-time (field
  index known statically) — `@o_s_*` access is
  `getelementptr %o_s_<qn>, ptr %p, i32 0, i32 <i>`.
- `%o_ret_<qn> = type { <val>, i64 }` — `val` then `err`, matching
  the C `{ <T> val; int64_t err; }` shape (lane-owned, but keeping
  C's order is free).
- `%o_en_<qn> = type { i32, [4 x i8], <payloadTy> }` — the tagged
  union C emits `{ int tag; union {…} u; }`. IR has no union: the
  lane keeps `i32` tag at offset 0, one `[4 x i8]` pad, and a single
  payload field typed as the **largest variant** (`%o_s_<qn>.<V>`
  with max size under the §6 model). The pad makes the payload
  offset 8 unconditionally — matching C's union offset whenever any
  variant carries an 8-aligned field (the common case) and diverging
  harmlessly otherwise (lane-owned layout). Payload access is a
  `getelementptr` to the payload field then `load`/`store` of *that
  variant's* type through the opaque `ptr` — legal under opaque
  pointers; declared `align` on the op is the variant's natural
  align, which the slot satisfies by construction.
- Lane-owned types never cross the rt boundary — no `rt_*` or extern
  fn takes `o_s_*`/`o_en_*`/`o_ret_*` (extern sigs map only to the
  boundary types above; a user extern naming a struct type is as
  unsatisfiable here as it is under the C lane — same failure, not a
  new hazard).

## 5. Frames, scopes, and the `RtScope` size problem

The one place an rt-internal layout would leak into emitted IR is
`RtScope` storage — `scope {}` blocks embed `RtScope scN` by value in
C, and `sizeof(RtScope)` is platform-dependent
(`pthread_mutex_t`+`pthread_cond_t` vs `SRWLOCK`+`CONDITION_VARIABLE`).
The lane never declares `RtScope`'s layout:

- **Non-frame `scope {}` blocks** — dynamic alloca, hoisted to
  the fn's entry block like every lane alloca:
  `%rtsz = call i64 @rt_scope_sizeof()` then
  `%sc<n> = alloca i8, i64 %rtsz, align 16`. Entry placement makes
  the storage execute-once and reused across loop iterations —
  exactly the C lane's block-local `RtScope _scN;` lifetime (an
  alloca sited inside a loop would accumulate stack per iteration —
  wrong). The block passes `%sc<n>` as `ptr` to
  `rt_scope_enter`/`rt_scope_leave` — the only operations the C
  lane performs on the storage too. `align 16` over-covers every
  platform mutex/condvar alignment on the supported targets
  (all ≤8); over-alignment of the *allocation* is always safe.
- **Frame `sc<i>` slots** — the frame type's tail is a `[0 x i8]`
  marker field; `rt_task_new`'s `bytes` argument becomes
  `add (i64 <fixed sizeof %o_frm_*>, mul (i64 <nscopes>, i64 %rtsz))`
  — `bytes` is already a runtime `i64` in the ABI, so the extra
  stride costs one load + multiply at spawn. `sc_i`'s address is
  `getelementptr i8, ptr %fr, i64 (fixed_off + i*%rtsz)`. The tail
  lives inside the same `rt_task_new` allocation — the frame-hold
  invariant `task_release_frame` relies on ("inner scopes are
  fields of the frame… a task that dies mid-block must not free()
  while children still point at them") holds unchanged: the scope
  storage dies with the frame block, no extra free path.
- **`rt_scope_sizeof()`** is a new additive rt.h entry
  (`int64_t rt_scope_sizeof(void) { return sizeof(RtScope); }`) —
  additive ABI only; the C lane's emitted text and the fixpoint are
  untouched. Named scopes already use `rt_scope_new()` heap scopes —
  opaque `ptr` throughout, unaffected.
- **`tls_scope` is boundary**: declared `@tls_scope = external
  thread_local global ptr` — rt.h's `extern _Thread_local
  RtScope *`, the only rt.c *variable* emitted code names. Poll
  prologue/epilogue load/store it directly (the save/restore
  choreography in items/suspension.md) — a plain `external
  global` would miscompile the TLS access.
- **The frame header is boundary**: `ptr cur_scope; i32 state`
  field-for-field with `RtFrame` — rt.c writes `fr->cur_scope` in
  `rt_task_new`'s spawn init and reads it in
  `task_release_frame`'s orphan-teardown walk, both through the
  `RtFrame*` cast. `child` (`ptr`) and `_dmark` (`ptr`) follow —
  rt.c's `RtFrame` only defines the first two fields; the rest of
  the prefix matches the C lane's decl order so a reader can diff
  the two emissions structurally, but only those two are ABI-locked. Result slot, params (`p_*`),
  frame slots (`v*`), then the scope tail marker — the full order
  lives in `items/suspension.md`.

## 6. The size model

The emitter needs byte sizes in exactly three places: enum
largest-variant selection, `%o_frm_*` fixed-prefix size (the
`rt_task_new` addend), and `getelementptr i8` arithmetic into the
frame scope tail. All three consume the same LP64 table:

| IR type | size | align |
|---|---|---|
| `i64` / `double` / `ptr` | 8 | 8 |
| `i32` | 4 | 4 |
| `i8` | 1 | 1 |
| aggregate | `align_up` layout per field order | max field align |

This is the *lane-internal* model, not a target query: every field
type's real alignment is ≤8 on every supported target (no SIMD
types, no `long double`, no over-aligned C types in the oxl surface).
Under a 32-bit or otherwise-narrower `--triple`, model sizes
over-reserve — enum payloads and frame prefixes grow, which is
correctness-safe because those layouts are lane-owned (§1's two
domains). Boundary types are never sized by the model: `OxlStr`/
`RtSlice`/`RtFnv`/`RtIface` layout comes from clang's datalayout on
both sides. Declared `align` on loads/stores uses the model value —
allocations (`rt_alloc` ≥16-aligned, `alloca` with explicit
`align 16`, `rt_task_new` heap blocks via malloc) always satisfy it;
under-declaring would be safe, over-declaring UB — the model never
exceeds a real alignment.

## 7. Semantics that must not drift

- `rt_*` call set identical to the C lane's: `rt_alloc`/
  `rt_alloc_own`/`rt_free`, `rt_borrow_*`/`rt_unborrow`,
  `rt_scope_*`, `rt_spawn*`/`rt_task_*`/`rt_run_root`,
  `rt_send/recv/close` + `_poll` forms, `rt_select_poll`,
  `rt_sleep_poll`/`rt_msleep_poll`, `rt_trap`/`rt_print*`/
  `rt_str_*`/slice ops/`rt_errstr`, `rt_is_root`, extern `rt_*`
  shims — the lane emits the same spelling, arity, and types the C
  lane does. Divergence is a bug: the ABI is the test (L4 parity).
- Trap/cancel flow is rt.c's — `rt_trap`'s longjmp+scope-propagation
  requires no emitted-code cooperation beyond calling it; unwind
  safety comes from the frame protocol, not from IR constructs (no
  `invoke`/`landingpad` anywhere — oxl has no exceptions).
- Atomicity lives in rt.c (`shared` cells, scope fields, chan
  internals) — emitted code issues plain `load`/`store`; the only
  atomic-visible emitted op is `rt_scas`-style calls. No `atomic`
  IR ops, no ordering attributes needed.
- `int` arithmetic is unguarded exactly where C is: `mul`/`add`/
  `sub` wrap (the C lane's unsigned-mul UB dodge has no IR analog —
  plain ops wrap by definition); `sdiv`/`srem` emit unguarded —
  division by zero is IR poison whose fault behavior is whatever
  the backend's `idiv` lowering produces (in practice the same
  SIGFPE-class fault the C lane's `/` gives). Making it a
  `rt_trap` would be an observable divergence, not a safety win. Byte-width ops keep the
  C lane's `& 0xff` result masking (`(uint8_t)(l op r)` →
  `and i32 …, 255` then `trunc i8`).
- `usleep` stays a real block — inline `call void @rt_usleep(i64)`,
  no parking rewrite.

## 8. Named divergences (fail loudly, never silently)

- **No `gnu11` surface** — statement expressions, `__builtin_*`,
  and GNU asm don't exist in IR; anything the C lane lowered through
  a GNU extension gets its native IR form (§2's alloca-result
  shape). Programs can't observe this.
- **`--emit-llvm`** keeps `out.ll` beside the binary for
  inspection — divergence-by-request only.
- **clang diagnostics** reference `.ll` text, not `.oxl` — the lane
  emits a `; source: <file>` banner per module so a failing build
  names its origin; source-level debug info is the parked DWARF
  item, not part of this contract.
- **`llvm.coro.*` absent** — the poll machine is hand-lowered like
  the C lane's; `items/suspension.md` names the parked alternative
  and its trigger.
