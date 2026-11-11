// rt-browser.mjs — browser flavor of the JS-target env shims.
// Contract per docs/specs/2026-11-10-web-target: the same names as
// rt-node.mjs, each returning err where the contract permits an err
// and trapping where it does not — never unbound. The DOM backend
// does not route through this file; it registers its own externs.

let S = null
const dec = new TextDecoder()

const s_of_js = (js) => S.rt_str(js)
const js_of_s = (s) => S.rt_str_cstr(s)
const empty_slice = () => ({ a: [], off: 0, len: 0, cap: 0 })
// rt_trap_native: full scope-marking machinery inside the scheduler,
// the checked __oxl_trap sentinel outside it (stub/test contexts)
const trap21 = () => S.rt_trap_native(21n)

export function install(api) {
  S = api
  const env = api.env
  const F = api.F

  // console-backed writer (lossy decode — documented divergence),
  // line-buffered so partial writes aren't split one line per call
  const wbuf = { 1: '', 2: '' }
  env.write = (fd, u8, off, len) => {
    wbuf[fd] = (wbuf[fd] || '') + dec.decode(u8.subarray(off, off + len))
    let i
    while ((i = wbuf[fd].indexOf('\n')) >= 0) {
      const line = wbuf[fd].slice(0, i)
      wbuf[fd] = wbuf[fd].slice(i + 1)
      if (fd === 2) console.error(line)
      else console.log(line)
    }
  }
  env.argv = [] // no argv: argv(0) reads as empty
  env.setExitCode = () => {}
  env.exitCodeOf = () => 0n
  env.exit = () => {} // no process exit

  const I = {
    rt_getenv: () => s_of_js(''),
    rt_exepath: () => s_of_js(''),
    rt_exit: () => {},
    rt_is_windows: () => 0n,
    rt_sigpipe_ignore: () => 0n,
    rt_errstr: (code) => s_of_js(`error ${code}`),
    rt_fexists: () => 0n,
    rt_isdir: () => 0n,
    rt_isfile: () => 0n,
    rt_isfilex: () => 0n,
    rt_islnk: () => 0n,
    rt_fullpath: (p) => s_of_js(js_of_s(p)),
    rt_readfile: () => ({ u8: new Uint8Array(0), off: 0, len: 0 }),
    rt_writefile: () => -22n, // EINVAL — err contract
    rt_open_read: () => -22n,
    rt_open_write: () => -22n,
    rt_open_write_mode: () => -22n,
    rt_fd_read: () => -22n,
    rt_fd_write: () => -22n,
    rt_fd_close: () => 0n,
    rt_remove: () => -22n,
    rt_mkdir: () => -22n,
    rt_rmdir: () => -22n,
    rt_rename: () => -22n,
    rt_chmod: () => -22n,
    rt_clone_attrs: () => -22n,
    rt_lsdir: () => empty_slice(),
    rt_file_readable: () => 0n,
    rt_strlen: (s) => BigInt(typeof s === 'string' ? s.length : 0),
    // blocking-capable surfaces with no browser equivalent — trap
    rt_proc_run: trap21,
    rt_proc_output: trap21,
    rt_sock_open: trap21,
    rt_sock_listen: trap21,
    rt_sock_accept: trap21,
    rt_sock_close: trap21,
    rt_sock_read: trap21,
    rt_sock_write: trap21,
    rt_sock_port: trap21,
    rt_sock_connect_ipv4: trap21,
    rt_bind_any: trap21,
    rt_set_reuseaddr: trap21,
    rt_set_rcvtimo: trap21,
    rt_set_rcvtimo_ms: trap21,
    rt_set_sndtimo: trap21,
    rt_lookup_start: trap21,
    rt_lookup_release: () => 0n,
    rt_sqlite_open: trap21,
    rt_sqlite_exec: trap21,
    rt_sqlite_query: trap21,
    rt_sqlite_close: trap21,
    rt_sqlite_exec_bind: trap21,
  }
  for (const k in I) F[k] = I[k]
}
