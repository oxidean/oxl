// rt-dom.mjs — DOM extern provider for extra/gui/dom (W6).
// Registers __oxl_ffi.oxl_dom_* at import time. Real `document` when
// present (the --html scaffold page); otherwise a headless object
// tree with the same append/dispatch semantics so node runs exercise
// the backend end-to-end — listener dispatch is synchronous in both
// flavors, matching the browser's event-delivery model.

const REAL = typeof document !== 'undefined' && document !== null

/* ---- element table: monotonic int handles -> nodes ---- */
const T = new Map()
let NEXT = 1
const put = (el) => { const h = NEXT++; T.set(h, el); el.__oxl_h = h; return h }
const get = (h) => T.get(Number(h)) || null
const del = (h) => T.delete(Number(h))

/* ---- headless node (mirrors the DOM surface the backend uses) ---- */
function hEl(tag) {
  return {
    __oxl_headless: true, tag, __oxl_h: 0,
    children: [], parent: null,
    props: { textContent: '', value: '', placeholder: '', disabled: false },
    style: {},
    listeners: new Map(), // 'click'|'input'|'keydown'|'oxl-close' -> [fns]
    addEventListener: function (k, f) {
      if (!this.listeners.has(k)) this.listeners.set(k, [])
      this.listeners.get(k).push(f)
    },
    dispatch: function (k, ev) {
      const l = this.listeners.get(k)
      if (l) for (const f of l) f(ev || {})
    },
  }
}
const hAppend = (p, c) => { c.parent = p; p.children.push(c) }
const hDetach = (p, c) => {
  const i = p.children.indexOf(c)
  if (i >= 0) p.children.splice(i, 1)
  if (c.parent === p) c.parent = null
}

/* ---- DOM event codes (mirrored in extra/gui/dom/dom.oxl) ---- */
const D_CLICK = 1n, D_INPUT = 2n, D_ENTER = 3n, D_ROWCLICK = 4n, D_CLOSE = 5n

/* event queue — pump_iter drains via oxl_dom_ev_* */
const EQ = []
const pushEv = (el, kind, aux) => EQ.push({ h: el.__oxl_h, kind, aux })

/* prop ids — extra/gui/gui.oxl's P_* table (stable ints) */
const P_TEXT = 1n, P_TITLE = 2n, P_PLACEHOLDER = 3n, P_ROWS = 4n

/* text-bearing prop field per element: <input> uses value for
 * P_TEXT, everything else uses textContent; P_PLACEHOLDER maps to
 * the input placeholder property. */
function propField(el, id) {
  if (id === P_PLACEHOLDER) return 'placeholder'
  if (id === P_TEXT && el.tag === 'input') return 'value'
  if (id === P_TEXT || id === P_TITLE) return 'textContent'
  return null
}
const pget = (el, f) => REAL ? el[f] : el.props[f]
const pset = (el, f, v) => { if (REAL) el[f] = v; else el.props[f] = v }

/* ---- root: #app when the page embeds one, else <body>; headless
 * gets a synthetic root so the window-attach path is identical ---- */
let ROOT = null
function root() {
  if (ROOT) return ROOT
  if (REAL) {
    ROOT = put(document.getElementById('app') || document.body)
  } else {
    ROOT = put(hEl('div'))
  }
  return ROOT
}

/* oxl-str -> js string (str args arrive as oxl-str objects, §7) */
let STR = (s) => String(s)

/* ---- install: fills __oxl_ffi.oxl_dom_* ---- */
export function install(api) {
  if (api && api.rt_str_cstr) STR = api.rt_str_cstr
  const F = (typeof globalThis.__oxl_ffi === 'object' && globalThis.__oxl_ffi !== null)
    ? globalThis.__oxl_ffi
    : (globalThis.__oxl_ffi = {})

  F.oxl_dom_root = () => BigInt(root())

  F.oxl_dom_create = (tag) => {
    const el = REAL ? document.createElement(String(STR(tag))) : hEl(String(STR(tag)))
    return BigInt(put(el))
  }

  F.oxl_dom_alive = (h) => (get(h) ? 1n : 0n)

  F.oxl_dom_destroy = (h) => {
    const el = get(h)
    if (!el) return
    if (REAL) {
      if (el.parentNode) el.parentNode.removeChild(el)
    } else if (el.parent) {
      hDetach(el.parent, el)
    }
    del(h)
  }

  F.oxl_dom_attach = (p, c) => {
    const pe = get(p), ce = get(c)
    if (!pe || !ce) return
    if (REAL) pe.appendChild(ce)
    else hAppend(pe, ce)
  }

  F.oxl_dom_detach = (p, c) => {
    const pe = get(p), ce = get(c)
    if (!pe || !ce) return
    if (REAL) { if (ce.parentNode === pe) pe.removeChild(ce) }
    else hDetach(pe, ce)
  }

  F.oxl_dom_set_text = (h, id, s) => {
    const el = get(h)
    if (!el) return
    const f = propField(el, BigInt(id))
    if (f === null) return
    pset(el, f, String(STR(s)))
  }

  /* cstr out — a JS string; the emitter decodes */
  F.oxl_dom_read_str = (h, id) => {
    const el = get(h)
    if (!el) return ''
    const f = propField(el, BigInt(id))
    if (f === null) return ''
    const v = pget(el, f)
    return v == null ? '' : String(v)
  }

  /* does this element answer the prop at all? */
  F.oxl_dom_read_has = (h, id) => {
    const el = get(h)
    if (!el) return 0n
    return propField(el, BigInt(id)) === null ? 0n : 1n
  }

  /* numeric props — P_ROWS: current child count (live, read-only) */
  F.oxl_dom_read_num = (h, id) => {
    const el = get(h)
    if (!el) return -1n
    if (BigInt(id) === P_ROWS) {
      return BigInt(REAL ? el.children.length : el.children.length)
    }
    return -1n
  }

  /* listeners — dom kind ints; the oxl side maps them to gui kinds */
  F.oxl_dom_listen = (h, kind) => {
    const el = get(h)
    if (!el) return
    const k = BigInt(kind)
    if (k === D_CLICK) {
      const f = () => pushEv(el, D_CLICK, 0n)
      REAL ? el.addEventListener('click', f) : el.addEventListener('click', f)
      return
    }
    if (k === D_INPUT) {
      const f = () => pushEv(el, D_INPUT, 0n)
      REAL ? el.addEventListener('input', f) : el.addEventListener('input', f)
      return
    }
    if (k === D_ENTER) {
      const f = (e) => { if ((e && e.key) === 'Enter') pushEv(el, D_ENTER, 0n) }
      REAL ? el.addEventListener('keydown', f) : el.addEventListener('keydown', f)
      return
    }
    if (k === D_ROWCLICK) {
      const f = () => {
        const p = el.parent ? el.parent : (REAL ? el.parentNode : el.parent)
        const idx = p ? p.children.indexOf(el) : -1
        pushEv(el, D_ROWCLICK, BigInt(idx < 0 ? 0 : idx))
      }
      REAL ? el.addEventListener('click', f) : el.addEventListener('click', f)
      return
    }
    if (k === D_CLOSE) {
      const f = () => pushEv(el, D_CLOSE, 0n)
      REAL ? el.addEventListener('oxl-close', f) : el.addEventListener('oxl-close', f)
      return
    }
  }

  /* event queue drain */
  F.oxl_dom_ev_next = () => (EQ.length ? BigInt(EQ[0].h) : 0n)
  F.oxl_dom_ev_pop = () => { if (EQ.length) EQ.shift() }
  F.oxl_dom_ev_kind = () => (EQ.length ? EQ[0].kind : 0n)
  F.oxl_dom_ev_aux = () => (EQ.length ? EQ[0].aux : 0n)

  /* headless dispatch — tests drive the listener path end-to-end;
   * a no-op under REAL (real pages dispatch via DOM events) */
  F.oxl_dom_fire = (h, kind) => {
    const el = get(h)
    if (!el || REAL) return
    const k = BigInt(kind)
    if (k === D_CLICK || k === D_ROWCLICK) el.dispatch('click')
    else if (k === D_INPUT) el.dispatch('input')
    else if (k === D_ENTER) el.dispatch('keydown', { key: 'Enter' })
    else if (k === D_CLOSE) el.dispatch('oxl-close')
  }

  /* headless inspection — tests read the tree the backend built */
  F.oxl_dom_tag = (h) => {
    const el = get(h)
    return el ? el.tag : ''
  }
  F.oxl_dom_kids = (h) => {
    const el = get(h)
    return el ? BigInt(el.children.length) : 0n
  }
}

/* self-install on import — the emitted bundle's boot imports this
 * module before oxl_main runs */
install()
