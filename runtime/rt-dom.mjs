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
/* appendChild move semantics: re-parenting pulls the child out of
 * its previous parent first */
const hAppend = (p, c) => {
  if (c.parent) {
    const i = c.parent.children.indexOf(c)
    if (i >= 0) c.parent.children.splice(i, 1)
  }
  c.parent = p
  p.children.push(c)
}
const hDetach = (p, c) => {
  const i = p.children.indexOf(c)
  if (i >= 0) p.children.splice(i, 1)
  if (c.parent === p) c.parent = null
}

/* ---- DOM event codes (mirrored in extra/gui/dom/dom.oxl) ---- */
const D_CLICK = 1n, D_INPUT = 2n, D_ENTER = 3n, D_ROWCLICK = 4n, D_CLOSE = 5n

/* event queue — pump_iter drains via oxl_dom_ev_* */
const EQ = []
/* pump edge — dom.backend() hands its wake chan in via set_edge so a
 * real DOM event lands as a scheduler nudge, not just an EQ row the
 * defensive 50ms timeout eventually finds */
let EDGE = null
let TRYSEND = null
const pushEv = (el, kind, aux, txt) => {
  EQ.push({ h: el.__oxl_h, kind, aux, txt })
  if (EDGE && TRYSEND) TRYSEND(EDGE, 1n)
}

/* prop ids — extra/gui/gui.oxl's P_* table (stable ints) */
const P_TEXT = 1n, P_TITLE = 2n, P_PLACEHOLDER = 3n, P_ROWS = 4n

/* text-bearing prop field per element: <input> uses value for
 * P_TEXT, everything else uses textContent; P_PLACEHOLDER maps to
 * the input placeholder property. */
function tagOf(el) {
  return REAL ? el.tagName.toLowerCase() : el.tag
}
function propField(el, id) {
  if (id === P_PLACEHOLDER) return 'placeholder'
  if (id === P_TEXT && tagOf(el) === 'input') return 'value'
  if (id === P_TEXT) return 'textContent'
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
  if (api && api.rt_try_send) TRYSEND = api.rt_try_send
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
      if (tagOf(el) !== 'ul') return -1n
      return BigInt(el.children.length)
    }
    return -1n
  }

  /* listeners — dom kind ints; the oxl side maps them to gui kinds.
   * Deduped per element+kind: re-attaching a row under a <ul>
   * re-calls listen and must not stack a second handler */
  F.oxl_dom_listen = (h, kind) => {
    const el = get(h)
    if (!el) return
    const k = BigInt(kind)
    const lk = el.__oxl_lk || (el.__oxl_lk = new Set())
    if (lk.has(k)) return
    lk.add(k)
    const lf = el.__oxl_lf || (el.__oxl_lf = new Map())
    const reg = (ev, f) => { el.addEventListener(ev, f); lf.set(k, [ev, f]) }
    if (k === D_CLICK) {
      reg('click', () => pushEv(el, D_CLICK, 0n))
      return
    }
    if (k === D_INPUT) {
      reg('input', () => pushEv(el, D_INPUT, 0n, pget(el, 'value')))
      return
    }
    if (k === D_ENTER) {
      reg('keydown', (e) => { if ((e && e.key) === 'Enter') pushEv(el, D_ENTER, 0n) })
      return
    }
    if (k === D_ROWCLICK) {
      reg('click', (e) => {
        if (REAL && e && e.target) {
          for (let x = e.target; x && x !== el; x = x.parentNode) {
            if (x.__oxl_h) return
          }
        }
        const p = REAL ? el.parentNode : el.parent
        const idx = p ? Array.prototype.indexOf.call(p.children, el) : -1
        pushEv(el, D_ROWCLICK, BigInt(idx < 0 ? 0 : idx))
      })
      return
    }
    if (k === D_CLOSE) {
      reg('oxl-close', () => pushEv(el, D_CLOSE, 0n))
      return
    }
  }

  /* detach must be able to drop a listener — the dedup set and the
   * fn table are kept in sync */
  F.oxl_dom_unlisten = (h, kind) => {
    const el = get(h)
    if (!el) return
    const k = BigInt(kind)
    const lf = el.__oxl_lf
    if (!lf || !lf.has(k)) return
    const [ev, f] = lf.get(k)
    if (REAL) {
      el.removeEventListener(ev, f)
    } else {
      const l = el.listeners.get(ev)
      if (l) { const i = l.indexOf(f); if (i >= 0) l.splice(i, 1) }
    }
    lf.delete(k)
    if (el.__oxl_lk) el.__oxl_lk.delete(k)
  }

  /* event queue drain */
  F.oxl_dom_ev_next = () => (EQ.length ? BigInt(EQ[0].h) : 0n)
  F.oxl_dom_ev_pop = () => { if (EQ.length) EQ.shift() }
  F.oxl_dom_ev_kind = () => (EQ.length ? EQ[0].kind : 0n)
  F.oxl_dom_ev_aux = () => (EQ.length ? EQ[0].aux : 0n)
  /* the value an input carried when its event fired — text_changed
   * reports fire-time state, not delivery-time state */
  F.oxl_dom_ev_txt = () => (EQ.length ? String(EQ[0].txt || '') : '')

  F.oxl_dom_set_edge = (ch) => { EDGE = ch }

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

  /* inline style — el.style[k] = v (headless carries a plain map) */
  F.oxl_dom_style = (h, name, v) => {
    const el = get(h)
    if (!el) return
    if (REAL) el.style.setProperty(String(STR(name)), String(STR(v)))
    else el.style[String(STR(name))] = String(STR(v))
  }

  /* headless inspection — tests read the tree the backend built */
  F.oxl_dom_tag = (h) => {
    const el = get(h)
    return el ? tagOf(el) : ''
  }
  F.oxl_dom_kids = (h) => {
    const el = get(h)
    return el ? BigInt(el.children.length) : 0n
  }
}

/* self-install on import — the emitted bundle's boot imports this
 * module before oxl_main runs */
install()
