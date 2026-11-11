// rt-node.mjs — node flavor of the JS-target env shims.
// install() is called by rt.mjs's __oxl_boot: it fills the byte
// writer, argv, exit and the env-dependent __oxl_ffi names before
// oxl_main runs. The full std/env surface is W5's deliverable;
// everything not yet wired is an err-stub or a trap, never an
// unbound name (a missing shim is a contract violation, not a
// TypeError).

import fs from 'node:fs'
import path from 'node:path'
import { execFileSync, spawnSync } from 'node:child_process'
import os from 'node:os'

let S = null // {u8,off,len} helpers from rt.mjs
const enc = new TextEncoder()
const dec = new TextDecoder()

const s_of_js = (js) => S.rt_str(js)
const js_of_s = (s) => S.rt_str_cstr(s)
const slice_of_u8 = (u8) => ({ a: u8, off: 0, len: u8.length, cap: u8.length })
const path_of = (s) => js_of_s(s)

function ok_int(v) {
  return BigInt(v)
}
function neg_errno(e) {
  // node surfaces errno as e.errno (negative) or a code string
  if (e && typeof e.errno === 'number') return BigInt(e.errno)
  const table = {
    ENOENT: -2, EINTR: -4, EIO: -5, EBADF: -9, EACCES: -13, EFAULT: -14,
    EBUSY: -16, EEXIST: -17, ENOTDIR: -20, EISDIR: -21, EINVAL: -22,
    ENFILE: -23, EMFILE: -24, EFBIG: -27, ENOSPC: -28, EPIPE: -32,
    EAGAIN: -35, EPERM: -1, ENOSYS: -38,
  }
  return BigInt(table[e && e.code] || -5)
}

function err_stub(name) {
  return () => 0n // err-returning contract where possible
}
function trap21() {
  // rt_trap_native: full scope-marking machinery inside the scheduler,
  // the checked __oxl_trap sentinel outside it (stub/test contexts)
  return S.rt_trap_native(21n)
}

export function install(api) {
  S = api
  const env = api.env
  const F = api.F

  // byte-exact stdout/stderr — fds 1/2 verbatim
  env.write = (fd, u8, off, len) => {
    fs.writeSync(fd, u8.subarray(off, off + len))
  }
  env.argv = process.argv.slice(1) // [script, ...args] — argv(0)=program
  env.setExitCode = (c) => {
    process.exitCode = Number(c)
  }
  env.exitCodeOf = () => BigInt(process.exitCode || 0)
  env.exit = (c) => process.exit(Number(c))

  const I = {
    /* ---------- process/env ---------- */
    rt_getenv: (name) => {
      const v = process.env[js_of_s(name)]
      return s_of_js(v === undefined ? '' : v)
    },
    rt_exepath: () => s_of_js(process.execPath),
    rt_exit: (c) => process.exit(Number(c)),
    rt_is_windows: () => (process.platform === 'win32' ? 1n : 0n),
    rt_sigpipe_ignore: () => 0n,
    rt_errstr: (code) => {
      code = Number(code)
      const table = {
        [-1]: 'operation not permitted', [-2]: 'no such file or directory',
        [-4]: 'interrupted system call', [-5]: 'input/output error',
        [-9]: 'bad file descriptor', [-13]: 'permission denied',
        [-16]: 'device or resource busy', [-17]: 'file exists',
        [-20]: 'not a directory', [-21]: 'is a directory',
        [-22]: 'invalid argument', [-24]: 'too many open files',
        [-28]: 'no space left on device', [-32]: 'broken pipe',
      }
      return s_of_js(table[code] || `error ${code}`)
    },

    /* ---------- fs ---------- */
    rt_fexists: (p) => (fs.existsSync(path_of(p)) ? 1n : 0n),
    rt_isdir: (p) => {
      try { return fs.statSync(path_of(p)).isDirectory() ? 1n : 0n } catch { return 0n }
    },
    rt_isfile: (p) => {
      try { return fs.statSync(path_of(p)).isFile() ? 1n : 0n } catch { return 0n }
    },
    rt_isfilex: (p) => {
      try { fs.accessSync(path_of(p), fs.constants.X_OK); return 1n } catch { return 0n }
    },
    rt_islnk: (p) => {
      try { return fs.lstatSync(path_of(p)).isSymbolicLink() ? 1n : 0n } catch { return 0n }
    },
    rt_fullpath: (p) => {
      try { return s_of_js(fs.realpathSync(path_of(p))) } catch { return s_of_js(path.resolve(path_of(p))) }
    },
    rt_readfile: (p) => {
      const b = fs.readFileSync(path_of(p))
      const u8 = new Uint8Array(b.length)
      u8.set(b)
      return { u8, off: 0, len: u8.length }
    },
    rt_writefile: (p, data) => {
      try {
        fs.writeFileSync(path_of(p), Buffer.from(data.u8.buffer, data.u8.byteOffset + data.off, data.len))
        return 0n
      } catch (e) { return neg_errno(e) }
    },
    rt_open_read: (p) => {
      try { return ok_int(fs.openSync(path_of(p), 'r')) } catch (e) { return neg_errno(e) }
    },
    rt_open_write: (p) => {
      try { return ok_int(fs.openSync(path_of(p), 'w')) } catch (e) { return neg_errno(e) }
    },
    rt_open_write_mode: (p, mode, src) => {
      try {
        return ok_int(fs.openSync(path_of(p), 'w', Number(mode)))
      } catch (e) { return neg_errno(e) }
    },
    rt_fd_read: (fd, b) => {
      try {
        const n = fs.readSync(Number(fd), b.a, b.off, b.len, null)
        return ok_int(n)
      } catch (e) { return e && e.code === 'EOF' ? 0n : neg_errno(e) }
    },
    rt_fd_write: (fd, b) => {
      try {
        return ok_int(fs.writeSync(Number(fd), b.a, b.off, b.len))
      } catch (e) { return neg_errno(e) }
    },
    rt_fd_close: (fd) => {
      try { fs.closeSync(Number(fd)); return 0n } catch (e) { return neg_errno(e) }
    },
    rt_remove: (p) => {
      try {
        const st = fs.lstatSync(path_of(p))
        if (st.isDirectory()) fs.rmdirSync(path_of(p))
        else fs.unlinkSync(path_of(p))
        return 0n
      } catch (e) { return neg_errno(e) }
    },
    rt_mkdir: (p) => {
      try { fs.mkdirSync(path_of(p)); return 0n } catch (e) { return neg_errno(e) }
    },
    rt_rmdir: (p) => {
      try { fs.rmdirSync(path_of(p)); return 0n } catch (e) { return neg_errno(e) }
    },
    rt_rename: (o, n) => {
      try { fs.renameSync(path_of(o), path_of(n)); return 0n } catch (e) { return neg_errno(e) }
    },
    rt_chmod: (p, mode) => {
      try { fs.chmodSync(path_of(p), Number(mode)); return 0n } catch (e) { return neg_errno(e) }
    },
    rt_clone_attrs: (sfd, dfd) => {
      try {
        const st = fs.fstatSync(Number(sfd))
        fs.fchmodSync(Number(dfd), st.mode)
        return 0n
      } catch (e) { return neg_errno(e) }
    },
    rt_lsdir: (p) => {
      try {
        const names = fs.readdirSync(path_of(p)).sort()
        return { a: names.map(s_of_js), off: 0, len: names.length, cap: names.length }
      } catch {
        return { a: [], off: 0, len: 0, cap: 0 }
      }
    },
    rt_file_readable: (p) => {
      try { fs.accessSync(path_of(p), fs.constants.R_OK); return 1n } catch { return 0n }
    },
    rt_strlen: (s) => BigInt(typeof s === 'string' ? s.length : 0),

    /* ---------- process spawn (sync surface) ---------- */
    // env is an override list merged onto the inherited environment —
    // `env_merge` parity: KEY=VALUE sets, a bare KEY strips the
    // inherited entry (never appended). An empty list means inherit.
    rt_proc_run: (argv, envv) => {
      try {
        const av = argv_exec(argv)
        const r = execFileSync(av[0], av.slice(1), {
          env: env_merge(envv),
          stdio: 'inherit',
        })
        return 0n
      } catch (e) {
        return ok_int(typeof e.status === 'number' ? e.status : 1)
      }
    },
    rt_proc_output: (argv, envv, outp, errp) => {
      // mut []byte params arrive boxed ({v: slice}) — reseat .v with
      // the captured streams and return the status, mirroring the
      // native RtSlice* writes; a negative return is the spawn/capture
      // err contract, nonzero exit is just status.
      try {
        const av = argv_exec(argv)
        const r = spawnSync(av[0], av.slice(1), {
          env: env_merge(envv),
          encoding: 'buffer',
        })
        if (r.error) return ok_int(-(r.error.errno || 1))
        if (outp) outp.v = slice_of_u8(new Uint8Array(r.stdout || []))
        if (errp) errp.v = slice_of_u8(new Uint8Array(r.stderr || []))
        return ok_int(r.status == null ? (r.signal ? 128 : 1) : r.status)
      } catch (e) {
        return ok_int(-(e.errno || 1))
      }
    },

    /* ---------- sqlite — C-lib dep, no js-lane mapping ---------- */
    rt_sqlite_open: trap21,
    rt_sqlite_exec: trap21,
    rt_sqlite_query: trap21,
    rt_sqlite_close: trap21,
    rt_sqlite_exec_bind: trap21,

    /* ---------- net — sync-blocking natives can't run on one thread.
     * These get the honest trap until W5's node-socket shims land. */
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
  }
  for (const k in I) F[k] = I[k]
}

// argv -> exec argv. argv(0) is the script path under node, which is
// not directly executable — a self-respawn (exec of argv(0)) is the
// program's own convention, so rewrite it to `node <script>` through
// process.execPath. Anything else executes verbatim.
function argv_exec(argv) {
  const av = []
  for (let i = 0; i < argv.len; i++) av.push(js_of_s(argv.a[argv.off + i]))
  const self = process.argv[1]
  if (av.length > 0 && self && path.resolve(av[0]) === path.resolve(self))
    return [process.execPath, self, ...av.slice(1)]
  return av
}

// merge an oxl []str override list onto the inherited environment —
// `env_merge` parity: KEY=VALUE sets/replaces, a bare KEY (no '=')
// strips the inherited entry rather than appending.
function env_merge(envv) {
  const merged = { ...process.env }
  if (!envv || envv.len <= 0) return merged
  for (let i = 0; i < envv.len; i++) {
    const kv = js_of_s(envv.a[envv.off + i])
    const eq = kv.indexOf('=')
    if (eq > 0) merged[kv.slice(0, eq)] = kv.slice(eq + 1)
    else delete merged[kv]
  }
  return merged
}
