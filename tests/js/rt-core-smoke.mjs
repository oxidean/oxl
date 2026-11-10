// tests/js/rt-core-smoke.mjs — W1 gate: hand-written driver exercising
// the frame-task contract the emitter generates: task_new + poll +
// spawn_task, scope enter/join/finish, traps through scope trees,
// defer stacks, str/slice/int helpers, shared cells, err registry.
// Run: node tests/js/rt-core-smoke.mjs

import * as rt from '../../runtime/rt.mjs'

let out = []
const say = (s) => out.push(s)

/* ---- a trivial susp fn's emitted shape ----
 * susp fn child(x:int): prints, sleeps 1ms, prints — modeled as a
 * 3-state poll machine exactly like codegen will emit. */
function POLL_child(fr, t) {
  switch (fr.state) {
    case 0:
      say('child a')
      fr.state = 1
      if (rt.rt_msleep_poll(20n, t) === rt.RT_PENDING) return rt.RT_PENDING
    /* fallthrough */
    case 1:
      say('child b')
      return rt.RT_READY
  }
  return rt.RT_READY
}

/* a susp fn that traps after registering a defer */
function POLL_boom(fr, t) {
  switch (fr.state) {
    case 0: {
      const mark = rt.rt_defer_mark()
      rt.rt_defer_push(() => say('boom defer ran'))
      fr.dmark = mark
      fr.state = 1
      rt.rt_trap(9n) // assertion-style trap
    }
    case 1:
      return rt.RT_READY
  }
  return rt.RT_READY
}

/* root poll: spawn children + a trapper in a named scope, sjoin it,
 * print the propagated err, defer at root level. */
function POLL_main(fr, t) {
  switch (fr.state) {
    case 0: {
      fr.dmark = rt.rt_defer_mark()
      rt.rt_defer_push(() => say('root defer'))
      fr.sc = rt.rt_scope_named()
      const a = rt.rt_task_new_in(fr.sc, POLL_child)
      rt.rt_spawn_task(a)
      const b = rt.rt_task_new_in(fr.sc, POLL_boom)
      rt.rt_spawn_task(b)
      fr.state = 1
      const r = rt.rt_scope_join_poll(fr.sc, t)
      if (r === rt.RT_PENDING) return rt.RT_PENDING
      /* fallthrough into finish */
    }
    case 1: {
      const e = rt.rt_scope_finish_named(fr.sc)
      say('scope err=' + e.toString())
      rt.rt_defer_drain_to(fr.dmark)
      return rt.RT_READY
    }
  }
  return rt.RT_READY
}

async function oxl_main() {
  const fr = rt.rt_task_new(POLL_main)
  return rt.rt_run_root(fr)
}

const rc = await rt.__oxl_boot(oxl_main)

/* ---- pure-value surface checks ---- */
const checks = []
const ck = (name, cond) => checks.push([name, !!cond])

ck('iadd wraps', rt.rt_iadd(9223372036854775807n, 1n) === -9223372036854775808n)
ck('ishl wraps', rt.rt_ishl(1n, 65n) === 2n) // shl &63 like rt.c
// traps outside a live scope are fatal (no catchable __oxl_trap) —
// inside-task coverage lands with the emitted-emitter gate
ck('idiv throws', (() => { try { rt.rt_idiv(1n, 0n); return false } catch { return true } })())
const s = rt.rt_str('héllo')
ck('str len utf8', s.len === 6)
ck('strcat', rt.rt_streq(rt.rt_strcat(rt.rt_str('a'), rt.rt_str('b')), rt.rt_str('ab')) === 1)
ck('substr', rt.rt_streq(rt.rt_substr(s, 1n, 4n), rt.rt_str('él')) === 1)
const sl = rt.rt_mkslice(2, 0n)
const sl2 = rt.rt_slice_push(sl, 7n)
ck('slice push', sl2.len === 3 && sl2.a[2] === 7n)
ck('sidx throws', (() => { try { rt.rt_sidx(sl2, 9n); return false } catch { return true } })())
const cell = rt.rt_mkshared(5n)
rt.rt_sadd(cell, 3n)
ck('scas', rt.rt_scas(cell, 8n, 9n) === 8n && cell.v === 9n)
const e1 = rt.rt_err_new(rt.rt_str('boom'))
const e2 = rt.rt_err_new(rt.rt_str('boom'))
ck('err dedupe', e1 === e2)
const w = rt.rt_err_wrap(rt.rt_str('wrap'), e1)
ck('wrap distinct', w !== e1 && rt.rt_err_cause(w) === e1)
ck('err msg', rt.rt_streq(rt.rt_err_msg(e1), rt.rt_str('boom')) === 1)
ck('is_root in boot', rt.rt_is_root() === 0) // outside task now
const ch = rt.rt_mkchan(0)
ck('chan closed0', rt.rt_chan_is_closed(ch) === 0n)
rt.rt_close(ch)
ck('chan closed1', rt.rt_chan_is_closed(ch) === 1n)

const expect = ['child a', 'boom defer ran', 'scope err=9', 'root defer']
// 'child b' never prints: boom's trap cancels the subtree, the sleep
// wake finds the task started+cancelled, and run_task settles it
// without polling again — the verbatim native gate.
const got = out
let pass = got.length === expect.length && got.every((v, i) => v === expect[i])
for (const [n, ok] of checks) {
  if (!ok) { pass = false; console.log('FAIL', n) }
}
if (!pass) {
  console.log('got:', got)
  console.log('want:', expect)
  process.exit(1)
}
console.log('rt-core-smoke: all green (' + checks.length + ' checks + ' + got.length + ' events)')
