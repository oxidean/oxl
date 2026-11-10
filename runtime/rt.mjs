// rt.mjs — oxl semantic runtime for the JS target.
//
// Port of runtime/rt.c's semantics minus everything a JS GC and a
// single-threaded event loop erase: no arenas, no ObjHdr heap lists,
// no mutexes/condvars, no thread pool, no refcount holds (GC owns
// task/frame memory). What remains verbatim: the scope tree + cancel +
// trap propagation protocol, the defer stack, the frame-task poll
// contract, chan rendezvous/buffer/select ordering invariants
// (claim/unlink rules from rt.c are the contract — a parked send
// claimed by select must not double-deliver), the err registry, and
// the str/slice operation set.
//
// Representation contract — docs/specs/2026-11-10-web-target/js-semantics.md:
//   int/err     BigInt (asIntN-64 helpers on every arithmetic edge)
//   float       Number
//   byte        Number masked &0xff
//   bool        boolean
//   str         {u8: Uint8Array, off: Number, len: Number}
//   []T         {a: Array|Uint8Array, off: Number, len: Number, cap: Number}
//   own/ref/mut plain JS reference
//   shared      {v: BigInt}
//   [v,err]     {val, err}
//   enum        {tag: Number, p0…}
//   iface       {obj, methods: {name: fn}}
//   chan        RtChan-analog object
//   externs     __oxl_ffi.<name> (globalThis — env files fill the rest)
//   nil         null / {a:null,off:0,len:0,cap:0}

export const RT_READY = 0
export const RT_PENDING = 1
export const RT_CANCEL = 2
export const RT_SEL_TMO = -2n
export const RT_SEL_ELSE = -3n

const I64 = (x) => BigInt.asIntN(64, x)
const U64 = (x) => BigInt.asUintN(64, x)

/* ---------------- env hook ----------------
 * The only pieces rt.mjs cannot supply itself: byte-oriented fd writes
 * (print/eprintln), argv, exit. rt-node.mjs / rt-browser.mjs fill this
 * at __oxl_boot time; the defaults keep the runtime loadable bare. */
export const env = {
  write(fd, u8, off, len) {
    // fallback: lossy decode — the documented browser divergence
    const s = new TextDecoder().decode(u8.subarray(off, off + len))
    if (fd === 2) {
      if (typeof console !== 'undefined') console.error(s.replace(/\n$/, ''))
    } else if (typeof console !== 'undefined') console.log(s.replace(/\n$/, ''))
  },
  exit(code) { /* browser: no exit */ },
  argv: [],
  setExitCode(code) { /* default no-op; node fills process.exitCode */ },
}

/* ---------------- ffi registry ----------------
 * Every `extern fn` emitted as __oxl_ffi.<name>. rt.mjs pre-fills the
 * semantic names below; rt-node.mjs / rt-browser.mjs fill the env set
 * before oxl_main runs. */
if (typeof globalThis.__oxl_ffi !== 'object' || globalThis.__oxl_ffi === null)
  globalThis.__oxl_ffi = {}

/* ---------------- task/scope state ---------------- */

let tls_task = null
let tls_scope = null
let tls_defers = null // foreign-context defer stack (no task)

const WK_RECV = 1
const WK_SEND = 2
const WK_SEL = 3
const WK_JOIN = 4
const WK_TRECV = 5 // thread waits — unreachable in JS; kept for parity
const WK_TSEND = 6
const WK_SLEEP = 7

const WS_ONSTACK = 0
const WS_PARKED = 1
const WS_WAKEREQ = 2

/* ---------------- run queue / scheduler ----------------
 * rq holds runnable frame tasks; drain polls each once. The drain is
 * bounded — after POLLS_PER_DRAIN the scheduler yields through a
 * task-level source (setImmediate under node, MessageChannel in
 * browsers) so timers, input and rendering interleave. When the queue
 * empties with the root task merely parked, a ref'd keepalive prevents
 * node from exiting — matching native, which waits for a wake rather
 * than reporting completion with work outstanding. */

const rq = []
const POLLS_PER_DRAIN = 64
let scheduled = false
let keepalive = null
let root_task = null // the task __oxl_boot drives; settled ends the boot

/* msgchan is built on first use — under node setImmediate always
 * wins and an eagerly-created port1 (a ref'd handle the moment an
 * onmessage lands) pins the event loop forever after tasks settle */
let msgchan = null
let mc_armed = false

function schedule_fast(fn) {
  if (typeof setImmediate === 'function') {
    setImmediate(fn)
  } else if (typeof MessageChannel !== 'undefined') {
    if (!msgchan) {
      msgchan = new MessageChannel()
      msgchan.port1.onmessage = () => drain()
    }
    // MessageChannel callbacks must not stack: arm once per drain
    if (!mc_armed) {
      mc_armed = true
      msgchan.port2.postMessage(null)
    }
  } else {
    setTimeout(fn, 0)
  }
}

function sched() {
  if (scheduled) return
  scheduled = true
  schedule_fast(drain)
}

function enqueue(t) {
  rq.push(t)
  sched()
}

function arm_keepalive() {
  if (keepalive !== null) return
  keepalive = setInterval(() => {}, 1 << 30)
  if (keepalive && keepalive.ref) keepalive.ref()
}

function disarm_keepalive() {
  if (keepalive === null) return
  clearInterval(keepalive)
  keepalive = null
}

function drain() {
  scheduled = false
  mc_armed = false
  let n = 0
  while (rq.length > 0 && n < POLLS_PER_DRAIN) {
    const t = rq.shift()
    n++
    /* the pool-worker's gate: a task cancelled after it started never
     * polls again — settle straight away; a never-started task still
     * polls once so its defers register */
    if (t.scope && t.scope.cancel && t.started) settle_skipped(t)
    else run_task(t)
  }
  if (rq.length > 0) {
    sched()
    return
  }
  // queue drained
  if (root_task && !root_task.settled) {
    // root merely parked — wakes arrive from timers/ffi edges
    arm_keepalive()
    return
  }
  if (root_task && root_task.settled) disarm_keepalive()
}

/* ---------------- borrow ledger (§9) ----------------
 * Per-task map obj -> mode (1 read, 2 mut). Same-task conflicts trap
 * exactly like rt.c; there is no object-global flag (the G1 port made
 * it per-task), and GC erases the heap-lifetime half entirely. */

const borrow_fallback = new Map()

function borrow_list(t) {
  return t ? t.borrows : borrow_fallback
}

function borrow_push(obj, mode) {
  const t = tls_task
  const m = borrow_list(t)
  const have = m.get(obj)
  if (have !== undefined && (mode === 2 || have === 2)) rt_trap(2n)
  m.set(obj, mode)
}

export function rt_borrow_read(obj) {
  if (obj !== null && obj !== undefined && (typeof obj === 'object' || typeof obj === 'function'))
    borrow_push(obj, 1)
}
export function rt_borrow_mut(obj) {
  if (obj !== null && obj !== undefined && (typeof obj === 'object' || typeof obj === 'function'))
    borrow_push(obj, 2)
}
export function rt_unborrow(obj) {
  if (obj === null || obj === undefined) return
  const t = tls_task
  borrow_list(t).delete(obj)
}

/* ---------------- scopes ----------------
 * {pending, trapped, cancel, err, parent, children, sib, wnext, dead,
 *  join_task, parked, owner, orphan, chans} — minus mutex/cv/arena/heap.
 * pending counts children tasks; join wakes join_task via scope_done. */

function scope_make() {
  return {
    pending: 0,
    trapped: 0,
    cancel: 0,
    err: 0n,
    parent: null,
    children: null,
    sib: null,
    wnext: null,
    dead: 0,
    join_task: null,
    parked: null,
    owner: null,
    orphan: 0,
    chans: null,
  }
}

export function rt_scope_make() {
  return scope_make()
}

/* rt_scope_enter(s): link s under tls_scope, then make it current.
 * A scope born under a cancelled parent starts cancelled; one born
 * under a dead parent stays unlinked (its own unlink must never reach
 * torn-down memory — same protocol as rt.c). */
export function rt_scope_enter(s) {
  s.parent = tls_scope
  s.owner = tls_task
  const p = s.parent
  if (p) {
    if (p.cancel || p.dead) s.cancel = 1
    if (p.dead) s.parent = null
    else {
      s.sib = p.children
      p.children = s
    }
  }
  tls_scope = s
}

/* drop s from its parent's descendant list — idempotent */
function scope_unlink(s) {
  const p = s.parent
  if (p) {
    let pp = p.children
    let prev = null
    while (pp) {
      if (pp === s) {
        if (prev) prev.sib = s.sib
        else p.children = s.sib
        break
      }
      prev = pp
      pp = pp.sib
    }
  }
  s.parent = null
  s.sib = null
}

/* detach every child of s: each survives with parent==null so its
 * later teardown/walk can never touch s once it's dead */
function scope_detach_children(s) {
  let c = s.children
  while (c) {
    const n = c.sib
    c.parent = null
    c.sib = null
    c = n
  }
  s.children = null
}

function scope_teardown(s) {
  s.dead = 1
  scope_unlink(s)
  scope_detach_children(s)
  scope_chans_teardown(s)
}

/* child-side teardown of an orphaned scope: the owner hold was a
 * memory protocol in rt.c — GC covers it here */
function scope_orphan_free(s) {
  scope_teardown(s)
}

function scope_done(s) {
  if (!s) return
  s.pending--
  if (s.pending <= 0) {
    const wake = s.join_task
    if (wake) {
      if (park_claim(wake)) {
        park_del(wake)
        rt_task_wake(wake)
      }
    } else if (s.orphan) {
      s.dead = 1
      scope_orphan_free(s)
    }
  }
}

function scope_pending_up(s) {
  if (s) s.pending++
}

/* heap-allocated scope for library code (http trap containment).
 * GC makes the "heap" part a no-op — a scope object is a scope object. */
export function rt_scope_new() {
  const s = scope_make()
  rt_scope_enter(s)
  return s
}

/* join a scope whose pending count already drained (all reachable JS
 * callers arrive here post-READY). A live join — pending > 0 — is a
 * blocking wait the single-threaded lane cannot express outside a
 * poll suspend; that call belongs to the frame path (rt_scope_join_poll)
 * and reaching it here means the emitter mislabeled the context. */
function join_scope(s) {
  if (s.pending > 0) rt_trap(21n)
  const err = s.trapped ? s.err : 0n
  s.dead = 1
  const up = s.parent
  scope_unlink(s)
  scope_detach_children(s)
  scope_chans_teardown(s)
  tls_scope = up
  return err
}

/* frame-task join: register as the scope's joiner, or READY if drained */
export function rt_scope_join_poll(s, t) {
  if (!s) return RT_READY
  if (park_add_scoped(t, s, WK_JOIN)) {
    /* cancelled before registration — no wake will find us; treat like
     * the drain path: READY so the poll's cancel check exits cleanly */
    return RT_CANCEL
  }
  if (s.pending > 0) {
    s.join_task = t
    return RT_PENDING
  }
  if (park_claim(t)) park_del(t)
  return RT_READY
}

export function rt_scope_finish(s) {
  const err = s.trapped ? s.err : 0n
  s.dead = 1
  const up = s.parent
  scope_unlink(s)
  scope_detach_children(s)
  scope_chans_teardown(s)
  tls_scope = up
  return err
}

/* propagate to the PARENT (the scope join restored to tls_scope) */
export function rt_scope_propagate(p, err) {
  if (p) {
    p.trapped = 1
    p.err = err
  } else {
    // escaped the top scope — abort like native
    throw { __oxl_fatal: `trap ${err} escaped top scope` }
  }
}

export function rt_scope_leave(s) {
  const err = join_scope(s)
  if (err) rt_scope_propagate(tls_scope, err)
}

export function rt_scope_try(s) {
  return s ? join_scope(s) : 0n
}

export function rt_scope_join_free(sv) {
  return rt_scope_try(sv)
}

/* named child scope handle (mkscope()): linked under the caller's
 * current scope but tls_scope is restored — the handle exists to be
 * spawned into and cancelled; the parent takes a pending hold so its
 * own join can never outlive the handle. */
export function rt_scope_named() {
  const s = scope_make()
  const cur = tls_scope
  if (cur) scope_pending_up(cur)
  rt_scope_enter(s)
  tls_scope = cur
  return s
}

/* named-scope join — poll form pairs rt_scope_join_poll + this at the
 * resume label, minus the wait and minus the tls_scope restore (the
 * joiner isn't leaving its own scope), then drops the parent's hold */
export function rt_scope_finish_named(sv) {
  const s = sv
  if (!s) return 0n
  const p = s.parent
  const e = rt_scope_finish(s)
  if (p) scope_done(p)
  return e
}

/* blocking named join — only non-frame contexts call it; under JS a
 * pending scope at this point is a single-thread deadlock, so it goes
 * through join_scope's trap(21) honesty path */
export function rt_scope_join_named(sv) {
  const s = sv
  if (!s) return 0n
  const p = s.parent
  const save = tls_scope
  const e = join_scope(s)
  tls_scope = save
  if (p) scope_done(p)
  return e
}

/* cancel every live child scope below s and force-wake their parked
 * tasks. A child that already committed teardown (dead) is skipped; a
 * live one gets a temp pending hold so its drain can't complete
 * between our mark and the wake — dropped after its subtree is done. */
function scope_cancel_tree(s) {
  let list = null
  for (let c = s.children; c; c = c.sib) {
    if (!c.dead) {
      c.cancel = 1
      c.pending++
      c.wnext = list
      list = c
    }
  }
  while (list) {
    const c = list
    list = c.wnext
    c.wnext = null
    scope_cancel_wake(c)
    scope_cancel_tree(c)
    scope_done(c)
  }
}

/* scoped cancel on a named scope (scancel(sc)): mark + wake its own
 * parked tasks + cancel the whole descendant subtree */
export function rt_scope_cancel(sv) {
  const s = sv
  if (!s || s.dead) return
  s.cancel = 1
  scope_cancel_wake(s)
  scope_cancel_tree(s)
}

/* ---------------- defers ----------------
 * Per task so entries survive suspends; function-entry mark, LIFO
 * drain to it at function exit and at task settle. JS closures capture
 * directly — no env structs. */

function defer_head() {
  return tls_task ? tls_task.defers : tls_defers
}

export function rt_defer_mark() {
  return defer_head()
}

export function rt_defer_push(fp) {
  const d = { fp, next: defer_head() }
  if (tls_task) tls_task.defers = d
  else tls_defers = d
  return d
}

export function rt_defer_drain_to(mark) {
  let hp = defer_head()
  while (hp !== mark) {
    const d = hp
    hp = d.next
    d.fp()
  }
  if (tls_task) tls_task.defers = mark
  else tls_defers = mark
}

function task_defers_drain(t) {
  while (t.defers) {
    const d = t.defers
    t.defers = d.next
    d.fp()
  }
}

/* ---------------- tasks ---------------- */

function task_make(poll, scope) {
  return {
    borrows: new Map(),
    poll,
    frame: null,
    scope,
    next: null,
    is_frame: 1,
    external: 0,
    is_root: 0,
    chan_res: null,
    parked: 0,
    park_scope: null,
    pnext: null,
    waitobj: null,
    waitkind: 0,
    sel: null,
    sel_arm: 0n,
    wstate: WS_ONSTACK,
    started: 0,
    defers: null,
    settled: false,
    _resolve: null,
  }
}

/* register t as parked on obj in scope s — the listed node is a queue
 * link, whoever unlinks it owns the wake path */
function park_add(t, s, obj, kind) {
  if (!t) return
  t.parked = 1
  t.waitobj = obj
  t.waitkind = kind
  if (!s) return
  t.park_scope = s
  t.pnext = s.parked
  s.parked = t
}

/* park registration + cancel check atomically (single-threaded): a
 * wake walk that ran before the insert left cancel set and no wake
 * behind — the caller must unwind instead of returning PENDING forever.
 * Returns 1 when the scope was already cancelled (NOT registered). */
function park_add_scoped(t, obj, kind) {
  const s = t.scope
  if (!s) {
    t.parked = 1
    t.waitobj = obj
    t.waitkind = kind
    return 0
  }
  if (s.cancel) return 1
  t.parked = 1
  t.park_scope = s
  t.waitobj = obj
  t.waitkind = kind
  t.pnext = s.parked
  s.parked = t
  return 0
}

/* drop t from its scope's parked list (idempotent; the claim itself
 * is the parked-flag flip) */
function park_del(t) {
  const s = t.park_scope
  if (!s) return
  let pp = s.parked
  let prev = null
  while (pp) {
    if (pp === t) {
      if (prev) prev.pnext = t.pnext
      else s.parked = t.pnext
      break
    }
    prev = pp
    pp = pp.pnext
  }
  t.park_scope = null
  t.pnext = null
}

/* the wake claim: whoever flips parked 1->0 owns the wake */
function park_claim(t) {
  if (t.parked === 1) {
    t.parked = 0
    return true
  }
  return false
}

/* re-enqueue a suspended frame task: the wstate swap serializes
 * against the driver's just-returned-PENDING window (a wake planted
 * while the task was still ONSTACK leaves WAKEREQ for the driver to
 * self-enqueue on) */
export function rt_task_wake(t) {
  const was = t.wstate
  t.wstate = WS_WAKEREQ
  if (was === WS_PARKED) enqueue(t)
}

/* cancel/unwind — the JS longjmp: run_task's catch settles the task.
 * Only fires from inside a poll (or drain-time defer drain). */
function task_unwind() {
  const t = tls_task
  if (!t) {
    // foreign context: nothing to settle — loud exit like native
    throw { __oxl_fatal: 'unwind outside task' }
  }
  park_del(t)
  throw { __oxl_unwind: true }
}

/* settle a finished task's frame: inner scopes are frame-owned, so a
 * task that dies mid-block orphans them — live orphans drain with
 * their last child, dead ones tear down inline (GC holds the frame). */
function task_release_frame(t, trapped) {
  if (t.is_frame && !trapped) {
    for (let x = t.frame.cur_scope; x && x !== t.scope; ) {
      x.orphan = 1
      x.cancel = 1
      const live = x.pending > 0
      if (live) x.pending++ // temp hold through the wake pass
      else x.dead = 1
      const up = x.parent
      if (!live) {
        scope_teardown(x)
        x = up
        continue
      }
      scope_cancel_wake(x)
      scope_done(x)
      x = up
    }
  }
  t.settled = true
  if (t._resolve) t._resolve()
}

function settle_common(t, trapped) {
  tls_task = t
  tls_scope = t.scope
  task_defers_drain(t)
  tls_task = null
  if (t.sel) rt_select_arm(t)
  scope_done(t.scope)
  task_release_frame(t, trapped)
}

/* the drain-loop settle for a task cancelled after it started:
 * never polls again — drain defers under a live catch (a suspending
 * defer unwinds back here like the trap path) then settle */
function settle_skipped(t) {
  tls_scope = t.scope
  tls_task = t
  try {
    task_defers_drain(t)
  } catch (e) {
    if (!e || (!e.__oxl_unwind && !e.__oxl_trap)) throw e
  }
  tls_task = null
  if (t.sel) rt_select_arm(t)
  scope_done(t.scope)
  task_release_frame(t, 0)
}

function run_task(t) {
  tls_scope = t.scope
  tls_task = t
  let trapped = 0
  t.wstate = WS_ONSTACK
  t.started = 1
  try {
    const r = t.poll(t.frame, t)
    if (r === RT_PENDING) {
      /* leaving the stack: a wake planted while we were still ONSTACK
       * left WAKEREQ — self-enqueue instead of parking */
      const was = t.wstate
      t.wstate = WS_PARKED
      tls_task = null
      if (was === WS_WAKEREQ) enqueue(t)
      return
    }
    /* READY / CANCEL both land here */
  } catch (e) {
    if (e && (e.__oxl_trap || e.__oxl_unwind)) {
      trapped = 1
    } else {
      tls_task = null
      throw e // genuine JS fault — propagate loudly
    }
  }
  /* a trap/unwind may have left tls_scope on a torn-down inner scope:
   * run defers in the task's spawn scope */
  settle_common(t, trapped)
}

/* ---------------- spawn / root ---------------- */

/* RtFrame: {cur_scope, state, ...emitted slots}. One object per task:
 * the task hangs off frame._task so generated code only carries fr. */
export function rt_task_new(poll) {
  const t = task_make(poll, tls_scope)
  const fr = { cur_scope: tls_scope, state: 0, _task: t }
  t.frame = fr
  return fr
}

/* scope-targeted spawn (goin(sc, f())): binds the task to the named
 * scope's pending count instead of the caller's innermost one */
export function rt_task_new_in(sv, poll) {
  const save = tls_scope
  tls_scope = sv
  const fr = rt_task_new(poll)
  tls_scope = save
  return fr
}

export function rt_spawn_task(fr) {
  const t = fr._task
  scope_pending_up(t.scope)
  enqueue(t)
}

/* frame task on the blocking pool — the single-threaded lane has no
 * blocking pool; spawnBlocking is spec-pinned trap(21) */
export function rt_spawnb_task(fr) {
  rt_trap(21n)
}

/* drive one frame task to completion — the root task (oxl_main) and
 * test-harness tasks. Resolves when the task settles; is_root lands
 * only when entered with no enclosing task (spawn-fallback analogs
 * leave the mark off, per the G contract). */
export function rt_run_root(fr) {
  const t = fr._task
  t.external = 1
  const prev = tls_task
  t.is_root = prev === null ? 1 : 0
  if (t.is_root && root_task === null) root_task = t
  const prev_scope = tls_scope
  tls_task = t
  tls_scope = t.scope
  const done = new Promise((res) => (t._resolve = res))
  enqueue(t)
  return done.then(() => {
    tls_task = prev
    tls_scope = prev_scope
    return t.trapped_result ? 1 : 0
  })
}

/* cooperative cancel check — a task is doomed when the scope it was
 * SPAWNED INTO (or a bound ancestor) is cancelled. Tasks merely
 * entered into a cancelled scope {} are not. */
export function rt_cancelled() {
  const t = tls_task
  return t && t.scope && t.scope.cancel ? 1 : 0
}

/* the gui.run gate: set only on the rt_run_root-entered task */
export function rt_is_root() {
  return tls_task && tls_task.is_root ? 1 : 0
}

/* the caller's innermost live scope as an opaque handle (curscope()) */
export function rt_scope_current() {
  return tls_scope
}

/* poll-driver prologue/epilogue: `rt_scope_set(fr.cur_scope)` on
 * frame entry restores the innermost scope the frame last saved;
 * `fr.cur_scope = rt_scope_current()` before each suspend return.
 * Plain assignment — no relinking (rt_scope_enter re-parents). */
export function rt_scope_set(s) {
  tls_scope = s
}

export function rt_task_data(t) {
  return t.chan_res
}

/* ---------------- traps ----------------
 * rt_trap marks the scope chain trapped/cancelled/orphaned, wakes the
 * parked tasks, cancels descendant subtrees, then throws — the JS
 * longjmp into run_task's catch. */

export function rt_trap(code) {
  const s = tls_scope
  const t = tls_task
  if (!s) {
    // no scope to contain — same as native's abort path
    while (tls_defers) {
      const d = tls_defers
      tls_defers = d.next
      d.fp()
    }
    throw { __oxl_fatal: `trap ${code} outside scope` }
  }
  if (t && t.is_frame) {
    /* mark the whole chain innermost -> spawn scope; inner scopes
     * orphan so their children outlive the frame (GC holds it) */
    for (let x = s; x; x = x.parent) {
      if (!x.trapped) {
        x.trapped = 1
        x.err = BigInt(code)
      }
      x.cancel = 1
      if (x !== t.scope) {
        x.orphan = 1
        x.pending++ // temp hold — dropped via scope_done below
      }
      if (x === t.scope) break
    }
    /* wake parked tasks so they observe cancel at resume instead of
     * parking forever on a chan nobody will serve */
    for (let x = s; x; x = x.parent) {
      scope_cancel_wake(x)
      if (x === t.scope) break
    }
    /* descendants of every marked scope: tasks parked inside sibling
     * subtrees aren't on this ancestor chain */
    for (let x = s; x; x = x.parent) {
      scope_cancel_tree(x)
      if (x === t.scope) break
    }
    /* drop the temp refs: a drained orphan tears down now; live ones
     * drain later under their last child's scope_done */
    for (let x = s; x; ) {
      const up = x.parent
      if (x !== t.scope) scope_done(x)
      if (x === t.scope) break
      x = up
    }
    tls_task = null
    throw { __oxl_trap: true, code: BigInt(code) }
  }
  if (!t) {
    while (tls_defers) {
      const d = tls_defers
      tls_defers = d.next
      d.fp()
    }
    throw { __oxl_fatal: `trap ${code}` }
  }
  /* non-frame task: same chain walk (checker bans scope{} in non-susp
   * fns, so the chain past t.scope is empty in practice) */
  for (let x = s; x; x = x.parent) {
    if (!x.trapped) {
      x.trapped = 1
      x.err = BigInt(code)
    }
    x.cancel = 1
    if (x !== t.scope) {
      x.orphan = 1
      x.pending++
    }
    if (x === t.scope) break
  }
  for (let x = s; x; x = x.parent) {
    scope_cancel_wake(x)
    if (x === t.scope) break
  }
  for (let x = s; x; x = x.parent) {
    scope_cancel_tree(x)
    if (x === t.scope) break
  }
  for (let x = s; x; ) {
    const up = x.parent
    if (x !== t.scope) {
      x.pending--
      if (x.pending <= 0) {
        x.dead = 1
        scope_teardown(x)
      } else {
        throw { __oxl_fatal: 'trap: task abandoned live scope' }
      }
    }
    if (x === t.scope) break
    x = up
  }
  task_unwind()
}

/* ---------------- shared cells ---------------- */

export function rt_mkshared(v) {
  return { v: BigInt(v), writer: 0 }
}
export function rt_sget(s) {
  return s.v
}
export function rt_sset(s, v) {
  s.v = BigInt(v)
}
export function rt_scas(s, expected, v) {
  const old = s.v
  if (old === BigInt(expected)) s.v = BigInt(v)
  return old
}
export function rt_sadd(s, delta) {
  const old = s.v
  s.v = I64(old + BigInt(delta))
  return old
}

/* latch pool — pooled close-latch cells; the pool exists in rt.c
 * because stale copies may CAS a recycled cell. GC erases the UAF
 * concern but the protocol stays: alloc hands a fresh/pooled cell,
 * free bumps the generation word then pools it. */
const LATCH_POOL_CAP = 4096
const latch_pool = []

export function rt_latch_alloc() {
  if (latch_pool.length > 0) return latch_pool.pop()
  return rt_mkshared(0n)
}
export function rt_latch_free(s) {
  rt_sadd(s, 1n) // g|1 -> g+2, next even generation
  if (latch_pool.length < LATCH_POOL_CAP) latch_pool.push(s)
}

/* ---------------- channels ----------------
 * One chan, poll surface only (there are no thread tasks). The claim/
 * unlink ordering invariants from rt.c are preserved verbatim:
 * a parked waiter owns its node until claimed; a resumed loser
 * unlinks. drop_elem thunks exist on `chan own T` but are no-ops —
 * GC owns payloads; the field stays so codegen shape parity is
 * mechanical. */

function SendReq_make(t, v) {
  return { t, v, next: null }
}

function mkchan(cap) {
  return {
    buf: cap > 0 ? new Array(cap).fill(null) : null,
    head: 0,
    count: 0,
    cap: Math.max(0, Number(cap)),
    has: 0,
    val: null,
    trecv: 0, // thread receivers — always 0 in JS (parity field)
    slot_owner: null,
    recvq: null,
    sendq: null,
    selq: null,
    closed: 0,
    drop_elem: null,
    owner: null,
    snext: null,
  }
}

export function rt_mkchan(cap) {
  return mkchan(Number(cap))
}

/* `chan own T` / scope-targeted mkchan: registers on the owning
 * scope's chans list so teardown closes it and reclaims queued
 * payloads via drop_elem. A dead scope refuses membership — the chan
 * is born closed. */
export function rt_mkchan_scoped(sv, cap, drop) {
  const c = mkchan(Number(cap))
  c.drop_elem = drop || null
  const s = sv
  if (!s) return c
  c.owner = s
  if (s.dead) {
    c.owner = null
    c.closed = 1
    return c
  }
  c.snext = s.chans
  s.chans = c
  return c
}

/* under-count check, count>0: pop the ring head, refill the slot from
 * a parked frame sender (FIFO + the sender's wake), deliver v. */
function chan_ring_pop(ch) {
  const v = ch.buf[ch.head]
  ch.buf[ch.head] = null
  ch.head = (ch.head + 1) % ch.cap
  ch.count--
  const s = chan_pop_send(ch)
  if (s) {
    ch.buf[(ch.head + ch.count) % ch.cap] = s.v
    ch.count++
    return { v, wake: s.t }
  }
  return { v, wake: null }
}

/* hand v to the first live select waiter; 1 when a waiter claimed */
function sel_fire(ch, v) {
  while (ch.selq) {
    const w = ch.selq
    ch.selq = w.next
    const s = w.sel
    if (!park_claim(s.t)) continue
    s.winner = w.slot
    s.t.chan_res = v
    s.t.sel_arm = BigInt(w.slot)
    rt_task_wake(s.t)
    return 1
  }
  return 0
}

/* park a frame receiver: node = the task itself on recvq */
function chan_park_recv(ch, t) {
  if (park_add_scoped(t, ch, WK_RECV)) return 1
  t.next = ch.recvq
  ch.recvq = t
  return 0
}

/* pop the first claimable parked receiver */
function chan_pop_recv(ch) {
  while (ch.recvq) {
    const r = ch.recvq
    ch.recvq = r.next
    r.next = null
    if (!park_claim(r)) continue // dead node
    park_del(r)
    return r
  }
  return null
}

/* pop the first claimable parked sender */
function chan_pop_send(ch) {
  while (ch.sendq) {
    const r = ch.sendq
    ch.sendq = r.next
    /* claim lost: the cancel pass owns the wake, but we already
     * unlinked the node — its walk can't find it, so the payload is
     * ours to drop */
    if (!park_claim(r.t)) {
      if (ch.drop_elem) ch.drop_elem(r.v)
      continue
    }
    park_del(r.t)
    return r
  }
  return null
}

/* nonblocking send: 1 = moved, 0 = full/closed. Delivery order mirrors
 * rt_send minus every wait. */
export function rt_try_send(ch, v) {
  if (ch.closed) {
    if (ch.drop_elem) ch.drop_elem(v)
    return 0
  }
  const r = chan_pop_recv(ch)
  if (r) {
    r.chan_res = v
    rt_task_wake(r)
    return 1
  }
  if (sel_fire(ch, v)) return 1
  if (ch.count < ch.cap) {
    ch.buf[(ch.head + ch.count) % ch.cap] = v
    ch.count++
    return 1
  }
  // trecv slot: no thread receivers in JS — fall to fail
  if (ch.drop_elem) ch.drop_elem(v)
  return 0
}

/* frame-task recv: READY delivers via task.chan_res; PENDING parks */
export function rt_recv_poll(ch, t) {
  if (ch.count > 0) {
    const { v, wake } = chan_ring_pop(ch)
    t.chan_res = v
    if (wake) rt_task_wake(wake)
    return RT_READY
  }
  const r = chan_pop_send(ch)
  if (r) {
    t.chan_res = r.v
    rt_task_wake(r.t)
    return RT_READY
  }
  if (ch.has || ch.closed) {
    t.chan_res = ch.has ? ch.val : null
    ch.has = 0
    ch.val = null
    return RT_READY
  }
  if (chan_park_recv(ch, t)) {
    /* cancelled before registration: no wake walk will ever find
     * us — unwind now instead of parking forever */
    task_unwind()
  }
  return RT_PENDING
}

/* frame-task send: same delivery order, parks on sendq when nothing
 * can take the value now */
export function rt_send_poll(ch, v, t) {
  const r = chan_pop_recv(ch)
  if (r) {
    r.chan_res = v
    rt_task_wake(r)
    return RT_READY
  }
  if (sel_fire(ch, v)) return RT_READY
  if (ch.count < ch.cap) {
    ch.buf[(ch.head + ch.count) % ch.cap] = v
    ch.count++
    return RT_READY
  }
  if (ch.closed) {
    /* silent completion still consumed the send — reclaim an
     * undelivered own payload through the chan thunk */
    if (ch.drop_elem) ch.drop_elem(v)
    return RT_READY // send on closed completes silently (v0 rule)
  }
  if (park_add_scoped(t, ch, WK_SEND)) {
    /* cancelled before registration: the payload never delivered —
     * reclaim it through the chan thunk like a cancel-wake does */
    if (ch.drop_elem) ch.drop_elem(v)
    task_unwind()
  }
  const sr = SendReq_make(t, v)
  sr.next = ch.sendq
  ch.sendq = sr
  return RT_PENDING
}

export function rt_close(ch) {
  ch.closed = 1
  /* drain parked waiters: receivers complete with the slot value
   * (matching the thread path); senders complete silently. */
  let r = ch.recvq
  ch.recvq = null
  let sq = ch.sendq
  ch.sendq = null
  let sw = ch.selq
  ch.selq = null
  let val = ch.has ? ch.val : null
  let had = ch.has
  let delivered = 0
  ch.has = 0
  ch.val = null
  while (r) {
    const n = r.next
    r.next = null
    if (park_claim(r)) {
      park_del(r)
      /* the deposited slot satisfies exactly one waiter */
      r.chan_res = delivered ? null : val
      delivered = 1
      rt_task_wake(r)
    }
    r = n
  }
  while (sq) {
    const n = sq.next
    if (park_claim(sq.t)) {
      park_del(sq.t)
      rt_task_wake(sq.t)
    }
    /* the payload was never delivered on either claim path */
    if (ch.drop_elem) ch.drop_elem(sq.v)
    sq = n
  }
  while (sw) {
    const n = sw.next
    const s = sw.sel
    if (park_claim(s.t)) {
      s.winner = sw.slot
      s.t.chan_res = delivered ? null : val
      delivered = 1
      s.t.sel_arm = BigInt(sw.slot)
      rt_task_wake(s.t)
    }
    sw = n
  }
  if (had && !delivered && ch.drop_elem) ch.drop_elem(val)
}

/* scope-teardown chan close: everything rt_close does plus drop_elem
 * on every still-queued payload */
export function rt_chan_teardown(ch) {
  ch.closed = 1
  if (ch.drop_elem) {
    while (ch.count > 0) {
      ch.drop_elem(ch.buf[ch.head])
      ch.buf[ch.head] = null
      ch.head = (ch.head + 1) % ch.cap
      ch.count--
    }
    if (ch.has) ch.drop_elem(ch.val)
    for (let q = ch.sendq; q; q = q.next) ch.drop_elem(q.v)
  }
  let r = ch.recvq
  ch.recvq = null
  let sq = ch.sendq
  ch.sendq = null
  let sw = ch.selq
  ch.selq = null
  ch.has = 0
  ch.val = null
  while (r) {
    const n = r.next
    r.next = null
    if (park_claim(r)) {
      park_del(r)
      r.chan_res = null
      rt_task_wake(r)
    }
    r = n
  }
  while (sq) {
    const n = sq.next
    if (park_claim(sq.t)) {
      park_del(sq.t)
      rt_task_wake(sq.t)
    }
    sq = n
  }
  while (sw) {
    const n = sw.next
    const s = sw.sel
    if (park_claim(s.t)) {
      s.winner = sw.slot
      s.t.chan_res = null
      s.t.sel_arm = BigInt(sw.slot)
      rt_task_wake(s.t)
    }
    sw = n
  }
}

/* teardown hook on scope.chans — membership is stable once dead
 * commits (rt_mkchan_scoped refuses dead scopes) */
function scope_chans_teardown(s) {
  const l = s.chans
  s.chans = null
  let c = l
  while (c) {
    const n = c.snext
    c.snext = null
    rt_chan_teardown(c)
    c = n
  }
}

export function rt_chan_is_closed(ch) {
  return ch.closed ? 1n : 0n
}

/* ---------------- sleep (poll) ----------------
 * The delay lives on a setTimeout so it never occupies the run queue;
 * the sleeper parks WK_SLEEP on its scope's parked list so
 * scope_cancel_wake can claim+wake it — a sibling trap no longer
 * waits out the timer. Timers are unref'd under node so a dying main
 * isn't held open by someone else's pending sleep. */

function sleep_poll(delay_ms, t) {
  /* cancel check + registration under one hold: a wake pass that runs
   * before park_add leaves no wake behind, and the timer becomes the
   * only waker — scope completion would wait out the whole delay for
   * a sibling trap that should exit fast */
  const s = t.scope
  if (s) {
    if (s.cancel) {
      return RT_READY // the post-poll rt_cancelled check dies
    }
    t.parked = 1
    t.park_scope = s
    t.waitobj = null
    t.waitkind = WK_SLEEP
    t.pnext = s.parked
    s.parked = t
  } else {
    park_add(t, null, null, WK_SLEEP)
  }
  const tm = setTimeout(() => {
    if (park_claim(t)) {
      park_del(t)
      rt_task_wake(t)
    }
  }, Number(delay_ms))
  if (tm && tm.unref) tm.unref()
  return RT_PENDING
}

export function rt_sleep_poll(secs, t) {
  return sleep_poll(BigInt(secs) * 1000n, t)
}
export function rt_msleep_poll(ms, t) {
  return sleep_poll(BigInt(ms), t)
}

/* ---------------- select ----------------
 * A parked select owns one SelW node per arm chan, linked on each
 * chan's selq. The first fire claims the task's parked flag so a
 * loser arm's node can never double-wake. Winner pick is uniform
 * random among ready arms — a random-start first-ready sweep is NOT
 * uniform (positional starvation the spec forbids). */

/* can this chan deliver now? — consumes like rt.c's sel_ready */
function sel_ready(ch) {
  if (ch.count > 0) {
    const { v, wake } = chan_ring_pop(ch)
    return { ready: 1, v, wake }
  }
  if (ch.sendq) {
    const r = ch.sendq
    ch.sendq = r.next
    let wake = null
    if (park_claim(r.t)) {
      park_del(r.t)
      wake = r.t
    }
    return { ready: 1, v: r.v, wake }
  }
  if (ch.has || ch.closed) {
    const v = ch.has ? ch.val : null
    ch.has = 0
    ch.val = null
    return { ready: 1, v, wake: null }
  }
  return { ready: 0, v: null, wake: null }
}

/* non-destructive peek — same predicate sel_ready gates on */
function sel_peek(ch) {
  return ch.count > 0 || ch.sendq || ch.has || ch.closed
}

export function rt_select_poll(chs, n, tmo_ms, has_else, t) {
  /* single-threaded fast path: peek can't disagree with consume inside
   * one synchronous call — collect the ready set once, pick uniformly,
   * consume that arm. */
  const ready = []
  for (let i = 0; i < n; i++) if (sel_peek(chs[i])) ready.push(i)
  if (ready.length > 0) {
    const pick = ready.length > 1 ? ready[(Math.random() * ready.length) | 0] : ready[0]
    const res = sel_ready(chs[pick])
    if (res.ready) {
      if (res.wake) rt_task_wake(res.wake)
      t.chan_res = res.v
      t.sel_arm = BigInt(pick)
      return RT_READY
    }
    // unreachable single-threaded; fall through to park
  }
  if (has_else) {
    /* else must never park — after the ready check take any arm that
     * still fires, and else only when none does */
    for (let i = 0; i < n; i++) {
      const res = sel_ready(chs[i])
      if (res.ready) {
        if (res.wake) rt_task_wake(res.wake)
        t.chan_res = res.v
        t.sel_arm = BigInt(i)
        return RT_READY
      }
    }
    /* a miss parks a single scheduler turn rather than reporting
     * else synchronously: native threads preempt, but under the
     * cooperative scheduler a synchronous else-poll never yields and
     * starves spawned peers forever. The waiters stay armed during
     * the turn, so a send that lands on it claims an arm through the
     * normal winner path — else only reports on a still-empty set. */
  }
  /* park: one SelW node per arm */
  const s = {
    winner: -1,
    n,
    tmo: BigInt(tmo_ms),
    t,
    w: [],
    timer: null,
    is_else: has_else ? 1 : 0,
  }
  t.sel = s
  if (park_add_scoped(t, s, WK_SEL)) {
    /* cancelled before registration: nothing armed yet — unwind
     * rather than park forever */
    t.sel = null
    task_unwind()
  }
  for (let i = 0; i < n; i++) {
    const w = { sel: s, slot: i, ch: chs[i], next: chs[i].selq }
    s.w.push(w)
    chs[i].selq = w
  }
  if (BigInt(tmo_ms) >= 0n || s.is_else) {
    const tm = setTimeout(() => {
      if (s.winner === -1) {
        s.winner = -2
        if (park_claim(t)) {
          t.sel_arm = s.is_else ? RT_SEL_ELSE : RT_SEL_TMO
          rt_task_wake(t)
        }
      }
    }, s.is_else ? 0 : Number(tmo_ms))
    s.timer = tm
    /* like rt_sleep's: a parked select must not pin the loop past a
     * settled root — unref where the env allows */
    if (tm && tm.unref) tm.unref()
  }
  return RT_PENDING
}

/* resume path: unlink the parked waiters and report which arm fired */
export function rt_select_arm(t) {
  let arm = t.sel_arm
  const s = t.sel
  t.sel = null
  if (!s) return arm
  park_del(t)
  for (let i = 0; i < s.n; i++) {
    const ch = s.w[i].ch
    let pp = ch.selq
    let prev = null
    while (pp) {
      if (pp === s.w[i]) {
        if (prev) prev.next = s.w[i].next
        else ch.selq = s.w[i].next
        break
      }
      prev = pp
      pp = pp.next
    }
  }
  return arm
}

/* scope cancel: force-wake every task parked inside s so suspended
 * tasks observe cancel at their resume point instead of hanging the
 * join. Claims the parked flag first — whoever wins owns the wake;
 * queue unlink is hygiene. */
function scope_cancel_wake(s) {
  for (;;) {
    const t = s.parked
    if (!t) return
    s.parked = t.pnext
    t.pnext = null
    t.park_scope = null
    /* joiners stay parked: they wake via scope_done when pending
     * drains — a premature finish would consume a live scope */
    if (t.waitkind === WK_JOIN) continue
    if (!park_claim(t)) continue
    switch (t.waitkind) {
      case WK_RECV: {
        const ch = t.waitobj
        let pp = ch.recvq
        let prev = null
        while (pp) {
          if (pp === t) {
            if (prev) prev.next = t.next
            else ch.recvq = t.next
            break
          }
          prev = pp
          pp = pp.next
        }
        t.next = null
        break
      }
      case WK_SEND: {
        const ch = t.waitobj
        let pp = ch.sendq
        let prev = null
        while (pp) {
          if (pp.t === t) {
            const d = pp
            if (prev) prev.next = d.next
            else ch.sendq = d.next
            /* send is statically a move: the parked payload was
             * never delivered, so the chan thunk reclaims it */
            if (ch.drop_elem) ch.drop_elem(d.v)
            break
          }
          prev = pp
          pp = pp.next
        }
        break
      }
      case WK_SEL: {
        const sel = t.waitobj
        /* fence off a live timer: with winner still -1 its claim
         * would target a task we've already woken */
        if (sel.winner === -1) sel.winner = -3
        for (let i = 0; i < sel.n; i++) {
          const ch = sel.w[i].ch
          let pp = ch.selq
          let prev = null
          while (pp) {
            if (pp === sel.w[i]) {
              if (prev) prev.next = sel.w[i].next
              else ch.selq = sel.w[i].next
              break
            }
            prev = pp
            pp = pp.next
          }
        }
        break
      }
      case WK_SLEEP:
        /* nothing to unlink: the timer races this same claim and
         * self-cleans on the loss */
        break
      // WK_TRECV/WK_TSEND: thread waits — unreachable in JS
      default:
        break
    }
    rt_task_wake(t)
  }
}

/* ---------------- strings (OxlStr {u8,off,len}) ---------------- */

const te = new TextEncoder()
const td = new TextDecoder()

export function rt_str(js) {
  const u8 = te.encode(js)
  return { u8, off: 0, len: u8.length }
}

/* literal: decode a base64 payload once into a shared backing buffer;
 * views reference (u8, off, len) */
const lit_cache = new Map()
export function rt_str_lit(b64) {
  let s = lit_cache.get(b64)
  if (s) return s
  let u8
  if (typeof atob === 'function') {
    const bin = atob(b64)
    u8 = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i)
  } else {
    u8 = new Uint8Array(Buffer.from(b64, 'base64'))
  }
  s = { u8, off: 0, len: u8.length }
  lit_cache.set(b64, s)
  return s
}

/* str -> JS string: the only legal UTF-16 crossing (ffi args, DOM) */
export function rt_str_cstr(s) {
  return td.decode(s.u8.subarray(s.off, s.off + s.len))
}

/* copy into fresh storage — own/scope both: GC erases the difference,
 * callers only observe that the result outlives its source view */
export function rt_str_own(s) {
  const u8 = new Uint8Array(s.len)
  u8.set(s.u8.subarray(s.off, s.off + s.len))
  return { u8, off: 0, len: s.len }
}
export function rt_str_scope(s) {
  return rt_str_own(s)
}
export function rt_str_free(s) {
  /* GC: nothing to release */
}

export function rt_strcat(a, b) {
  const u8 = new Uint8Array(a.len + b.len)
  u8.set(a.u8.subarray(a.off, a.off + a.len))
  u8.set(b.u8.subarray(b.off, b.off + b.len), a.len)
  return { u8, off: 0, len: a.len + b.len }
}

export function rt_streq(a, b) {
  if (a.len !== b.len) return 0
  for (let i = 0; i < a.len; i++)
    if (a.u8[a.off + i] !== b.u8[b.off + i]) return 0
  return 1
}

export function rt_str_cmp(a, b) {
  const n = Math.min(a.len, b.len)
  for (let i = 0; i < n; i++) {
    const d = a.u8[a.off + i] - b.u8[b.off + i]
    if (d !== 0) return BigInt(d)
  }
  return BigInt(a.len - b.len)
}

export function rt_itoa(v) {
  return rt_str(BigInt(v).toString())
}

export function rt_len(s) {
  return BigInt(s.len)
}

export function rt_byteat(s, i) {
  i = BigInt(i)
  if (i < 0n || i >= BigInt(s.len)) return -1n
  return BigInt(s.u8[s.off + Number(i)])
}

export function rt_substr(s, a, b) {
  a = Number(a)
  b = Number(b)
  if (a < 0) a = 0
  if (b > s.len) b = s.len
  if (a >= b) return { u8: new Uint8Array(0), off: 0, len: 0 }
  const u8 = new Uint8Array(b - a)
  u8.set(s.u8.subarray(s.off + a, s.off + b))
  return { u8, off: 0, len: b - a }
}

export function rt_find(s, sub) {
  outer: for (let i = 0; i + sub.len <= s.len; i++) {
    for (let j = 0; j < sub.len; j++)
      if (s.u8[s.off + i + j] !== sub.u8[sub.off + j]) continue outer
    return BigInt(i)
  }
  return -1n
}

/* strtoll/strtod semantics: parse a leading numeric prefix, garbage
 * yields 0 — decode through the edge string, then replicate */
export function rt_atoi(s) {
  const js = rt_str_cstr(s)
  const m = js.match(/^[\s]*([+-]?[0-9]+)/)
  if (!m) return 0n
  try {
    return I64(BigInt(m[1]))
  } catch {
    return m[1][0] === '-' ? (-1n << 63n) : (1n << 63n) - 1n
  }
}
export function rt_atof(s) {
  /* strtod parity: inf/infinity/nan literals parse, overflow gives
   * Inf (not 0), only a non-numeric head yields 0 */
  const js = rt_str_cstr(s)
  const m = js.match(/^[\s]*([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[+-]?(?:inf(?:inity)?|nan))/i)
  if (!m) return 0
  return parseFloat(m[1])
}

/* %.15g / %.*g emulation — g = shortest of fixed/exponential at the
 * requested significant digits, trailing zeros stripped, e-notation
 * when exp < -4 or >= prec */
function ftoa_g(v, prec) {
  if (Number.isNaN(v)) return 'nan'
  if (!Number.isFinite(v)) return v < 0 ? '-inf' : 'inf'
  if (v === 0) return '0'
  const exp = Math.floor(Math.log10(Math.abs(v)))
  let out
  if (exp < -4 || exp >= prec) {
    out = v.toExponential(prec - 1)
    // strip mantissa trailing zeros, then normalize exponent
    out = out.replace(/(\.\d*?)0+e/, '$1e').replace(/\.e/, 'e')
    out = out.replace(/e([+-]?)(\d+)$/, (m, sign, d) => `e${sign === '-' ? '-' : '+'}${d.padStart(2, '0')}`)
  } else {
    out = v.toPrecision(prec)
    out = out.replace(/(\.\d*?)0+$/, '$1').replace(/\.$/, '')
  }
  return out
}
export function rt_ftoa(v) {
  return rt_str(ftoa_g(v, 15))
}
export function rt_ftoa_p(v, prec) {
  const p = Number(prec)
  if (p <= 0) return rt_str('')
  try {
    return rt_str(ftoa_g(v, p))
  } catch {
    return rt_str('')
  }
}

/* ---------------- slices ({a,off,len,cap}) ---------------- */

export function rt_mkslice(n, zero) {
  n = Number(n)
  const a = new Array(n)
  for (let i = 0; i < n; i++) a[i] = zero
  return { a, off: 0, len: n, cap: n }
}

/* []byte always Uint8Array-backed: externs write into the caller's
 * slice, so the backing must be a shared typed-array view */
export function rt_mkslice_b(n) {
  n = Number(n)
  return { a: new Uint8Array(n), off: 0, len: n, cap: n }
}

export function rt_slice_push(s, v) {
  if (s.len < s.cap) {
    s.a[s.off + s.len] = v
    return { a: s.a, off: s.off, len: s.len + 1, cap: s.cap }
  }
  const ncap = s.cap > 0 ? s.cap * 2 : 4
  const nb = new Array(ncap)
  for (let i = 0; i < s.len; i++) nb[i] = s.a[s.off + i]
  nb[s.len] = v
  return { a: nb, off: 0, len: s.len + 1, cap: ncap }
}

export function rt_slice_push_b(s, v) {
  /* int-domain byte narrows to Number before the Uint8Array store —
   * a bare & would mix BigInt with a Number literal */
  const b = typeof v === 'bigint' ? Number(v & 0xffn) : v & 0xff
  if (s.len < s.cap) {
    s.a[s.off + s.len] = b
    return { a: s.a, off: s.off, len: s.len + 1, cap: s.cap }
  }
  const ncap = s.cap > 0 ? s.cap * 2 : 4
  const nb = new Uint8Array(ncap)
  nb.set(s.a.subarray(s.off, s.off + s.len))
  nb[s.len] = b
  return { a: nb, off: 0, len: s.len + 1, cap: ncap }
}

/* own []T: boxed view — {v: slice} where v re-seats on grow */
export function rt_slice_own(s) {
  return { v: { a: s.a, off: s.off, len: s.len, cap: s.cap } }
}

/* bounds-checked slice index — the trap is on the BigInt domain
 * before narrowing to the array's Number index */
export function rt_sidx(s, i) {
  i = BigInt(i)
  if (i < 0n || i >= BigInt(s.len)) rt_trap(10n)
  const v = s.a[s.off + Number(i)]
  /* byte-slice backings are Uint8Array — the Number element widens
   * to the int domain's BigInt (mirror of rt_sidx_set's narrow) */
  return s.a instanceof Uint8Array ? BigInt(v) : v
}
export function rt_sidx_set(s, i, v) {
  i = BigInt(i)
  if (i < 0n || i >= BigInt(s.len)) rt_trap(10n)
  /* byte-slice backings are Uint8Array — a BigInt (int domain) value
   * narrows to the byte's masked Number rather than throwing */
  if (s.a instanceof Uint8Array && typeof v === 'bigint') {
    s.a[s.off + Number(i)] = Number(v & 0xffn)
    return
  }
  s.a[s.off + Number(i)] = v
}

/* s[a:b] — bounds-trap; the sub-view aliases the parent backing */
export function rt_sslice(s, a, b) {
  a = BigInt(a)
  b = BigInt(b)
  if (a < 0n || b < a || b > BigInt(s.len)) rt_trap(10n)
  return {
    a: s.a,
    off: s.off + Number(a),
    len: Number(b - a),
    cap: s.cap - Number(a),
  }
}

/* str index — same bounds rule on the byte view */
export function rt_str_idx(s, i) {
  i = BigInt(i)
  if (i < 0n || i >= BigInt(s.len)) rt_trap(10n)
  return BigInt(s.u8[s.off + Number(i)])
}

/* str as []byte: copy of the string bytes (slice mutation can never
 * write back into the str) */
export function rt_bytes_str(s) {
  const u8 = new Uint8Array(s.len)
  u8.set(s.u8.subarray(s.off, s.off + s.len))
  return { a: u8, off: 0, len: s.len, cap: s.len }
}

/* []byte as str: a view — mutation through the slice is visible
 * through the str (native keeps the same direction) */
export function rt_str_bytes(b) {
  return { u8: b.a, off: b.off, len: b.len }
}

/* ---------------- byte buffers ---------------- */

export function rt_mkbuf(size) {
  return new Uint8Array(Number(size))
}
export function rt_bufstr(buf, n) {
  n = Number(n)
  const u8 = new Uint8Array(n)
  u8.set(buf.subarray(0, n))
  return { u8, off: 0, len: n }
}
export function rt_poke8(buf, off, v) {
  buf[Number(off)] = Number(v) & 0xff
}
export function rt_poke16(buf, off, v) {
  off = Number(off)
  v = Number(v)
  buf[off] = (v >> 8) & 0xff
  buf[off + 1] = v & 0xff
}
export function rt_poke32(buf, off, v) {
  off = Number(off)
  v = Number(v)
  buf[off] = (v >>> 24) & 0xff
  buf[off + 1] = (v >>> 16) & 0xff
  buf[off + 2] = (v >>> 8) & 0xff
  buf[off + 3] = v & 0xff
}
export function rt_htons(v) {
  v = Number(v) & 0xffff
  return BigInt(((v & 0xff) << 8) | (v >> 8))
}
export function rt_htonl(v) {
  v = Number(v) >>> 0
  return BigInt(
    ((v & 0xff) << 24) | ((v & 0xff00) << 8) | ((v >>> 8) & 0xff00) | (v >>> 24)
  )
}

/* ---------------- print ----------------
 * Raw bytes to the env writer — a str can carry arbitrary bytes via
 * []byte as str, so decode would corrupt non-UTF-8 payloads. */

export function rt_print_str(s) {
  env.write(1, s.u8, s.off, s.len)
}
export function rt_println_str(s) {
  env.write(1, s.u8, s.off, s.len)
  env.write(1, NL8, 0, 1)
}
const NL8 = new Uint8Array([10])
export function rt_print_i64(v) {
  env.write(1, te.encode(BigInt(v).toString()), 0, 0)
  const e = te.encode(BigInt(v).toString())
  env.write(1, e, 0, e.length)
}
export function rt_println_i64(v) {
  rt_print_i64(v)
  env.write(1, NL8, 0, 1)
}
export function rt_print_f64(v) {
  const e = te.encode(ftoa_g(v, 15))
  env.write(1, e, 0, e.length)
}
export function rt_println_f64(v) {
  rt_print_f64(v)
  env.write(1, NL8, 0, 1)
}
export function rt_eprint_str(s) {
  env.write(2, s.u8, s.off, s.len)
}
export function rt_eprintln_str(s) {
  env.write(2, s.u8, s.off, s.len)
  env.write(2, NL8, 0, 1)
}

/* ---------------- int helpers (asIntN-64 at every edge) ---------------- */

export const rt_iadd = (a, b) => I64(BigInt(a) + BigInt(b))
export const rt_isub = (a, b) => I64(BigInt(a) - BigInt(b))
export const rt_imul = (a, b) => I64(BigInt(a) * BigInt(b))
export const rt_idiv = (a, b) => {
  a = BigInt(a)
  b = BigInt(b)
  if (b === 0n) rt_trap(4n)
  return I64(a / b)
}
export const rt_imod = (a, b) => {
  a = BigInt(a)
  b = BigInt(b)
  if (b === 0n) rt_trap(4n)
  return I64(a % b)
}
export const rt_ineg = (a) => I64(-BigInt(a))
export const rt_ishl = (a, b) => I64(BigInt(a) << (BigInt(b) & 63n))
export const rt_ishr = (a, b) => I64(BigInt(a) >> (BigInt(b) & 63n))
export const rt_iand = (a, b) => I64(BigInt(a) & BigInt(b))
export const rt_ior = (a, b) => I64(BigInt(a) | BigInt(b))
export const rt_ixor = (a, b) => I64(BigInt(a) ^ BigInt(b))
export const rt_inot = (a) => I64(~BigInt(a))
export const rt_to_num = (i) => Number(i)
export const rt_to_int = (n) => I64(BigInt(n))

/* ---------------- err registry (RT_ERR_BASE FNV, verbatim) ---------------- */

const RT_ERR_BASE = 1 << 20
const RT_ERR_BUCKETS = 512
const RT_ERR_MAX = 65536

const err_tab = []
const err_bkt = new Int32Array(RT_ERR_BUCKETS)
let err_ovf = -1

function err_hash(s) {
  let h = 1469598103934665603n
  for (let i = 0; i < s.len; i++) {
    h ^= BigInt(s.u8[s.off + i])
    h = U64(h * 1099511628211n)
  }
  return h
}

function err_put(msg, cause) {
  const b = Number(err_hash(msg) % BigInt(RT_ERR_BUCKETS))
  const ent = {
    next: err_bkt[b],
    mlen: msg.len,
    cause: BigInt(cause || 0n),
    msg: rt_str_own(msg),
  }
  err_bkt[b] = err_tab.length + 1
  err_tab.push(ent)
  return BigInt(RT_ERR_BASE + err_tab.length - 1)
}

/* control-flow sentinels intern before any user message (rt.c's seed
 * order — codes must stay identical with native) */
const err_seeds = ['EOF', 'io: no progress', 'io: short write']
let err_seeded = false
function err_seed() {
  if (err_seeded) return
  err_seeded = true
  for (const m of err_seeds) err_put(rt_str(m), 0n)
}

export function rt_err_new(msg) {
  err_seed()
  const b = Number(err_hash(msg) % BigInt(RT_ERR_BUCKETS))
  for (let i = err_bkt[b]; i; i = err_tab[i - 1].next) {
    const e = err_tab[i - 1]
    if (e.mlen === msg.len && rt_streq(e.msg, msg)) return BigInt(RT_ERR_BASE + i - 1)
  }
  if (err_ovf >= 0) return BigInt(err_ovf)
  if (err_tab.length === RT_ERR_MAX - 1) {
    err_ovf = Number(err_put(rt_str('error registry full'), 0n))
    return BigInt(err_ovf)
  }
  return err_put(msg, 0n)
}

/* wrap appends WITHOUT dedupe — a wrapped error is a distinct value
 * even when its text repeats, so the cause slot survives */
export function rt_err_wrap(msg, cause) {
  err_seed()
  if (err_ovf >= 0) return BigInt(err_ovf)
  if (err_tab.length === RT_ERR_MAX - 1) {
    err_ovf = Number(err_put(rt_str('error registry full'), 0n))
    return BigInt(err_ovf)
  }
  const ent = { next: 0, mlen: msg.len, cause: BigInt(cause), msg: rt_str_own(msg) }
  err_tab.push(ent)
  return BigInt(RT_ERR_BASE + err_tab.length - 1)
}

export function rt_err_cause(code) {
  if (code == null) return 0n
  const i = Number(BigInt(code) - BigInt(RT_ERR_BASE))
  if (i < 0) return 0n
  return i < err_tab.length ? err_tab[i].cause : 0n
}

export function rt_err_msg(code) {
  if (code == null) return rt_str('')
  const i = Number(BigInt(code) - BigInt(RT_ERR_BASE))
  if (i < 0 || i >= err_tab.length) return rt_str('')
  return err_tab[i].msg
}

/* ---------------- time (universal) ---------------- */

export function rt_now() {
  return BigInt(Math.floor(Date.now() / 1000))
}
export function rt_now_ms() {
  return BigInt(Date.now())
}
/* matches rt.c's rt_timestr format: local wall clock ISO-ish */
export function rt_timestr() {
  const d = new Date()
  const p = (n, w = 2) => String(n).padStart(w, '0')
  return rt_str(
    `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
      `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`
  )
}

/* ---------------- math (rt_m_* — pure Math) ---------------- */

export const rt_m_sqrt = (x) => Math.sqrt(x)
export const rt_m_pow = (x, y) => Math.pow(x, y)
export const rt_m_exp = (x) => Math.exp(x)
export const rt_m_log = (x) => Math.log(x)
export const rt_m_log10 = (x) => Math.log10(x)
export const rt_m_log2 = (x) => Math.log2(x)
export const rt_m_floor = (x) => Math.floor(x)
export const rt_m_ceil = (x) => Math.ceil(x)
export const rt_m_trunc = (x) => Math.trunc(x)
export const rt_m_round = (x) => Math.round(x)
export const rt_m_fmod = (x, y) => x % y
export const rt_m_fabs = (x) => Math.abs(x)
export const rt_m_hypot = (x, y) => Math.hypot(x, y)
export const rt_m_sin = (x) => Math.sin(x)
export const rt_m_cos = (x) => Math.cos(x)
export const rt_m_tan = (x) => Math.tan(x)
export const rt_m_asin = (x) => Math.asin(x)
export const rt_m_acos = (x) => Math.acos(x)
export const rt_m_atan = (x) => Math.atan(x)
export const rt_m_atan2 = (y, x) => Math.atan2(y, x)
export const rt_m_nan = () => NaN
export const rt_m_inf = (sign) => (BigInt(sign) < 0n ? -Infinity : Infinity)
export const rt_m_isnan = (x) => (Number.isNaN(x) ? 1n : 0n)
export const rt_m_isinf = (x) => (x === Infinity || x === -Infinity ? 1n : 0n)
export const rt_m_signbit = (x) => (Object.is(x, -0) || x < 0 ? 1n : 0n)

/* ---------------- args (env-provided) ---------------- */

export function rt_argc() {
  return BigInt(env.argv.length)
}
export function rt_argv(i) {
  i = Number(i)
  if (i < 0 || i >= env.argv.length) return rt_str('')
  return rt_str(String(env.argv[i]))
}
export function rt_set_args(list) {
  env.argv = list
}

/* ---------------- blocking surface — spec §8: traps, not silence --
 * Thread-task-only entry points have no single-threaded equivalent.
 * The poll forms above carry every reachable susp path; reaching one
 * of these means the emitter let a blocking call through a non-susp
 * context, and we fail loudly instead of diverging silently. */

function blocked(name) {
  return () => rt_trap(21n)
}
export const rt_send = blocked('rt_send')
export const rt_recv = blocked('rt_recv')
export const rt_usleep = blocked('rt_usleep')
export const rt_msleep = blocked('rt_msleep')
export const rt_sleep = blocked('rt_sleep')
export const rt_spawn = blocked('rt_spawn')
export const rt_spawnb = blocked('rt_spawnb')

/* ---------------- alloc erasure ----------------
 * GC owns lifetime: emitted code allocates plain objects/Arrays/Maps.
 * These exist for ffi-surface completeness only. */
export function rt_alloc(n) {
  return new Uint8Array(Number(n))
}
export function rt_alloc_own(n) {
  return new Uint8Array(Number(n))
}
export function rt_free(obj) {}

/* ---------------- ffi pre-fill (semantic names) ---------------- */

{
  const F = globalThis.__oxl_ffi
  const fill = {
    rt_err_new,
    rt_err_wrap,
    rt_err_cause,
    rt_err_msg,
    rt_scope_new,
    rt_scope_join_free,
    rt_latch_alloc,
    rt_latch_free,
    rt_itoa,
    rt_ftoa_p,
    rt_str_own,
    rt_str_scope,
    rt_str_free,
    rt_str_cmp,
    rt_free,
    rt_chan_is_closed,
    rt_now,
    rt_now_ms,
    rt_timestr,
    rt_argc,
    rt_argv,
    rt_mkshared,
    rt_sget,
    rt_sset,
    rt_scas,
    rt_sadd,
    rt_m_sqrt,
    rt_m_pow,
    rt_m_exp,
    rt_m_log,
    rt_m_log10,
    rt_m_log2,
    rt_m_floor,
    rt_m_ceil,
    rt_m_trunc,
    rt_m_round,
    rt_m_fmod,
    rt_m_fabs,
    rt_m_hypot,
    rt_m_sin,
    rt_m_cos,
    rt_m_tan,
    rt_m_asin,
    rt_m_acos,
    rt_m_atan,
    rt_m_atan2,
    rt_m_nan,
    rt_m_inf,
    rt_m_isnan,
    rt_m_isinf,
    rt_m_signbit,
    // blocking surface — honest traps
    rt_send,
    rt_recv,
    rt_usleep,
    rt_msleep,
    rt_sleep,
    rt_spawnb_task,
  }
  for (const k in fill) F[k] = fill[k]
}

/* ---------------- entry ----------------
 * __oxl_boot(main_entry): selects the env flavor, fills __oxl_ffi,
 * installs args, creates the base scope, then runs the emitted
 * oxl_main root frame task to completion. main_entry is the emitted
 * function — it builds the root frame and returns rt.run_root(fr),
 * a Promise. */

export async function __oxl_boot(main_entry) {
  const isNode =
    typeof process !== 'undefined' &&
    process.versions &&
    typeof process.versions.node === 'string'
  if (isNode) {
    await import('./rt-node.mjs').then((m) => m.install(rt_exports_api()))
  } else {
    await import('./rt-browser.mjs').then((m) => m.install(rt_exports_api()))
  }
  /* the dom provider self-selects real-document vs headless tree at
   * import; programs that never link extra/gui/dom pay one tiny
   * module load for a table nobody reads. */
  await import('./rt-dom.mjs').then((m) => m.install(rt_exports_api()))
  const base = scope_make()
  rt_scope_enter(base)
  try {
    const trapped = await main_entry()
    const code = env.exitCodeOf ? env.exitCodeOf() : 0
    rt_scope_leave(base)
    if (isNode) env.setExitCode(code)
    return trapped ? 1 : 0
  } catch (e) {
    /* a fatal that escaped the scope tree mirrors native's abort:
     * the message lands on stderr, the run exits nonzero. Without
     * the boundary the throw surfaces as an unhandled rejection —
     * node's crash banner, not the trap line native prints. */
    if (e && e.__oxl_fatal) {
      const m = te.encode(String(e.__oxl_fatal))
      env.write(2, m, 0, m.length)
      env.write(2, NL8, 0, 1)
      env.setExitCode(1)
      return 1
    }
    throw e // genuine JS fault — propagate loudly
  }
}

/* passed to the env module's install(): lets it wire writers, argv,
 * exit, and the rest of __oxl_ffi without re-importing (import cycles
 * would deadlock the module graph) */
function rt_exports_api() {
  return { env, F: globalThis.__oxl_ffi, rt_str, rt_str_cstr }
}

/* ---------------- test entry ----------------
 * testm=1 wraps test_* fns in scope+try like the C path; the emitter
 * drives each through rt_run_root and prints the same
 * `test_x … ok` lines. */
export function rt_test_scope() {
  const s = scope_make()
  rt_scope_enter(s)
  return s
}
