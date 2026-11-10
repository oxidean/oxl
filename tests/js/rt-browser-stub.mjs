// tests/js/rt-browser-stub.mjs — W5 gate: the browser env flavor's
// contract — every extern it registers is bound (never unbound), the
// err-contract names return codes instead of throwing, and the
// blocking-capable names trap only via the checked {__oxl_trap,
// code:21n} path — nothing unchecked escapes.
// Run: node tests/js/rt-browser-stub.mjs

import { install } from '../../runtime/rt-browser.mjs'

let fails = 0
const say = (s) => process.stdout.write(s + '\n')
const ok = (cond, name) => {
  if (!cond) {
    fails++
    say('FAIL ' + name)
  }
}

/* fake api surface — install() only touches env/F/rt_str/rt_str_cstr */
const F = {}
const env = {}
install({
  env,
  F,
  rt_str: (js) => js,
  rt_str_cstr: (s) => s,
})

/* ---- env surface ---- */
ok(Array.isArray(env.argv) && env.argv.length === 0, 'env.argv empty')
ok(typeof env.write === 'function', 'env.write bound')
let threw = false
try {
  env.write(1, new TextEncoder().encode('x\n'), 0, 2)
} catch (e) { threw = true }
ok(!threw, 'env.write no-throw')
ok(typeof env.setExitCode === 'function' && typeof env.exitCodeOf === 'function', 'exit fns bound')
ok(env.exitCodeOf() === 0n, 'exitCodeOf 0n')
threw = false
try { env.exit(1n) } catch (e) { threw = true }
ok(!threw, 'env.exit no-throw (no process exit in-browser)')

/* ---- err-contract names: must return a value, never throw ---- */
const errRet = {
  rt_writefile: -22n, rt_open_read: -22n, rt_open_write: -22n,
  rt_open_write_mode: -22n, rt_fd_read: -22n, rt_fd_write: -22n,
  rt_remove: -22n, rt_mkdir: -22n, rt_rmdir: -22n, rt_rename: -22n,
  rt_chmod: -22n, rt_clone_attrs: -22n,
  rt_fd_close: 0n, rt_lookup_release: 0n,
  rt_fexists: 0n, rt_isdir: 0n, rt_isfile: 0n, rt_isfilex: 0n,
  rt_islnk: 0n, rt_is_windows: 0n, rt_sigpipe_ignore: 0n,
  rt_file_readable: 0n,
}
for (const [name, want] of Object.entries(errRet)) {
  ok(typeof F[name] === 'function', name + ' bound')
  let v, t2 = false
  try { v = F[name]('x', 'y', 'z') } catch (e) { t2 = true }
  ok(!t2, name + ' no-throw')
  ok(v === want, name + ' returns ' + want)
}

/* str-returning names — empty is the stub's documented answer */
for (const name of ['rt_getenv', 'rt_exepath', 'rt_errstr']) {
  ok(typeof F[name] === 'function', name + ' bound')
  const v = F[name]('x')
  ok(typeof v === 'string', name + ' returns str')
}
ok(F.rt_fullpath('a/b') === 'a/b', 'rt_fullpath identity')
ok(typeof F.rt_strlen('abc') === 'bigint', 'rt_strlen bigint')

/* slice shapes — the emitter's {a,off,len,cap} / {u8,off,len} contract */
const ls = F.rt_lsdir('x')
ok(ls && Array.isArray(ls.a) && ls.len === 0 && ls.off === 0, 'rt_lsdir empty slice')
const rf = F.rt_readfile('x')
ok(rf && rf.u8 instanceof Uint8Array && rf.len === 0, 'rt_readfile empty u8')

/* ---- trap-contract names: throw ONLY the checked __oxl_trap 21 ---- */
const trappers = [
  'rt_proc_run', 'rt_proc_output', 'rt_sock_open', 'rt_sock_listen',
  'rt_sock_accept', 'rt_sock_close', 'rt_sock_read', 'rt_sock_write',
  'rt_sock_port', 'rt_sock_connect_ipv4', 'rt_bind_any',
  'rt_set_reuseaddr', 'rt_set_rcvtimo', 'rt_set_rcvtimo_ms',
  'rt_set_sndtimo', 'rt_lookup_start',
]
for (const name of trappers) {
  ok(typeof F[name] === 'function', name + ' bound')
  let caught = null
  try { F[name]() } catch (e) { caught = e }
  ok(caught !== null, name + ' traps')
  ok(caught && caught.__oxl_trap === true && caught.code === 21n,
     name + ' checked trap21')
}

/* ---- nothing else may throw: sweep every registered name ---- */
for (const name of Object.keys(F)) {
  if (trappers.includes(name)) continue
  let t3 = false
  try { F[name]('x', 'y', 'z', 'w') } catch (e) { t3 = true }
  ok(!t3, name + ' unchecked-throw sweep')
}

if (fails === 0) {
  say('rt-browser-stub: all green')
} else {
  say('rt-browser-stub: ' + fails + ' FAIL')
  process.exit(1)
}
