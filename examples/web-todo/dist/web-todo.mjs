import * as rt from './rt.mjs'

let o_g_gui_P_TEXT;let o_g_gui_P_TITLE;let o_g_gui_P_PLACEHOLDER;let o_g_gui_P_ROWS;let o_g_gui_g_event_cap;let o_g_gui_g_cmd_cap;let o_g_gui_g_drain_ms;let o_g_gui_g_running;let o_g_gui_g_eb;let o_g_gui_g_cb;let o_g_gui_g_sess;let o_g_gui_g_last_dropped;let o_g_gui_g_rp;let o_g_gui_g_rp_n;let o_g_gui_g_rp_mu;let o_g_gui_g_cells;let o_g_gui_g_cells_n;let o_g_gui_g_cell_mu;let o_g_dom_D_CLICK;let o_g_dom_D_INPUT;let o_g_dom_D_ENTER;let o_g_dom_D_ROWCLICK;let o_g_dom_D_CLOSE;let o_g_dom_g_alive;let o_g_g_rows;let o_g_g_rows_mu;let o_g_g_lb;let o_g_g_en;let o_g_g_add;let o_g_g_d;let o_g_g_selftest;let o_g_g_hb;let o_g_g_rm;function o_frm_gui_send_marked() { const t = rt.rt_task_new(o_poll_gui_send_marked); t.v0 = null; t.v1 = null; return t }
function o_frm_gui_send_event() { const t = rt.rt_task_new(o_poll_gui_send_event); t.v0 = null; return t }
function o_frm_gui_dispatch_loop() { const t = rt.rt_task_new(o_poll_gui_dispatch_loop); t.v0 = 0n; t.v1 = null; return t }
function o_frm_gui_watcher() { const t = rt.rt_task_new(o_poll_gui_watcher); return t }
function o_frm_gui_pump_task() { const t = rt.rt_task_new(o_poll_gui_pump_task); t.v0 = null; t.v1 = 0n; return t }
function o_frm_gui_run() { const t = rt.rt_task_new(o_poll_gui_run); t.v0 = null; t.v1 = null; t.v2 = 0n; t.v3 = 0n; t.v4 = null; t.sc0 = null; return t }
function o_frm_gui_create() { const t = rt.rt_task_new(o_poll_gui_create); t.v0 = null; t.v1 = null; t.v2 = null; t.v3 = 0n; t.v4 = null; t.v5 = 0n; return t }
function o_frm_gui_window() { const t = rt.rt_task_new(o_poll_gui_window); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_vbox() { const t = rt.rt_task_new(o_poll_gui_vbox); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_hbox() { const t = rt.rt_task_new(o_poll_gui_hbox); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_label() { const t = rt.rt_task_new(o_poll_gui_label); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_button() { const t = rt.rt_task_new(o_poll_gui_button); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_entry() { const t = rt.rt_task_new(o_poll_gui_entry); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_list() { const t = rt.rt_task_new(o_poll_gui_list); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_scrolled() { const t = rt.rt_task_new(o_poll_gui_scrolled); t.v0 = 0n; t.v1 = 0n; return t }
function o_frm_gui_read_prop() { const t = rt.rt_task_new(o_poll_gui_read_prop); t.v0 = null; t.v1 = null; t.v2 = null; t.v3 = 0n; t.v4 = null; t.v5 = {tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}; t.v6 = {u8:null,off:0,len:0}; return t }
function o_frm_gui_Entry_text() { const t = rt.rt_task_new(o_poll_gui_Entry_text); t.v0 = {tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}; t.v1 = 0n; t.v2 = {tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}; t.v3 = {u8:null,off:0,len:0}; t.v4 = false; t.v5 = 0n; return t }
function o_frm_gui_List_rows() { const t = rt.rt_task_new(o_poll_gui_List_rows); t.v0 = {tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}; t.v1 = 0n; t.v2 = {tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}; t.v3 = 0n; return t }
function o_frm_time_sleep_ms() { const t = rt.rt_task_new(o_poll_time_sleep_ms); return t }
function o_frm_add_row() { const t = rt.rt_task_new(o_poll_add_row); t.v0 = {f_h:0n}; t.v1 = 0n; t.v2 = {f_h:0n}; t.v3 = 0n; t.v4 = {f_h:0n}; t.v5 = 0n; return t }
function o_frm_wait_rows() { const t = rt.rt_task_new(o_poll_wait_rows); t.v0 = 0n; t.v1 = 0n; t.v2 = 0n; return t }
function o_frm_selftest_drive() { const t = rt.rt_task_new(o_poll_selftest_drive); t.v0 = 0n; t.v1 = 0n; t.v2 = 0n; t.v3 = 0n; t.v4 = 0n; t.v5 = 0n; t.v6 = 0n; t.v7 = 0n; t.v8 = 0n; return t }
function o_frm_ui() { const t = rt.rt_task_new(o_poll_ui); t.v0 = {f_h:0n}; t.v1 = 0n; t.v2 = {f_h:0n}; t.v3 = 0n; t.v4 = {f_h:0n}; t.v5 = 0n; t.v6 = {f_h:0n}; t.v7 = 0n; t.v8 = {f_h:0n}; t.v9 = 0n; t.v10 = {f_h:0n}; t.v11 = 0n; t.v12 = null; t.v13 = {u8:null,off:0,len:0}; t.v14 = 0n; t.v15 = 0n; t.v16 = {u8:null,off:0,len:0}; t.v17 = 0n; return t }
function o_frm_main() { const t = rt.rt_task_new(o_poll_main); t.v0 = 0n; return t }
const o_vt_gui_Backend_dom_Dom = {wake: (o, ...a) => o_f_dom_Dom_wake(o, ...a),stop: (o, ...a) => o_f_dom_Dom_stop(o, ...a),pump_fin: (o, ...a) => o_f_dom_Dom_pump_fin(o, ...a),stopped: (o, ...a) => o_f_dom_Dom_stopped(o, ...a),pump_edge: (o, ...a) => o_f_dom_Dom_pump_edge(o, ...a),pump_iter: (o, ...a) => o_f_dom_Dom_pump_iter(o, ...a),susp_pump: (o, ...a) => o_f_dom_Dom_susp_pump(o, ...a),pump: (o, ...a) => o_f_dom_Dom_pump(o, ...a),destroy: (o, ...a) => o_f_dom_Dom_destroy(o, ...a),detach: (o, ...a) => o_f_dom_Dom_detach(o, ...a),attach: (o, ...a) => o_f_dom_Dom_attach(o, ...a),set_prop: (o, ...a) => o_f_dom_Dom_set_prop(o, ...a),new: (o, ...a) => o_f_dom_Dom_new(o, ...a),};
const o_vt_gui_Widget_gui_Window = {kind: (o, ...a) => o_f_gui_Window_kind(o, ...a),handle: (o, ...a) => o_f_gui_Window_handle(o, ...a),};
const o_vt_gui_Widget_gui_Entry = {kind: (o, ...a) => o_f_gui_Entry_kind(o, ...a),handle: (o, ...a) => o_f_gui_Entry_handle(o, ...a),};
const o_vt_gui_Widget_gui_VBox = {kind: (o, ...a) => o_f_gui_VBox_kind(o, ...a),handle: (o, ...a) => o_f_gui_VBox_handle(o, ...a),};
const o_vt_gui_Widget_gui_Scrolled = {kind: (o, ...a) => o_f_gui_Scrolled_kind(o, ...a),handle: (o, ...a) => o_f_gui_Scrolled_handle(o, ...a),};
const o_vt_gui_Widget_gui_List = {kind: (o, ...a) => o_f_gui_List_kind(o, ...a),handle: (o, ...a) => o_f_gui_List_handle(o, ...a),};
const o_vt_gui_Widget_gui_Button = {kind: (o, ...a) => o_f_gui_Button_kind(o, ...a),handle: (o, ...a) => o_f_gui_Button_handle(o, ...a),};
const o_vt_gui_Widget_gui_Label = {kind: (o, ...a) => o_f_gui_Label_kind(o, ...a),handle: (o, ...a) => o_f_gui_Label_handle(o, ...a),};
const o_vt_gui_Widget_gui_HBox = {kind: (o, ...a) => o_f_gui_HBox_kind(o, ...a),handle: (o, ...a) => o_f_gui_HBox_handle(o, ...a),};
function o_poll_gui_send_marked(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    fr.v0 = o_f_gui_cell_take();
    const _da0_0 = fr.v0;
    const _da0_1 = fr.p_n;
    rt.rt_defer_push(() => { (o_f_gui_credit_marker(_da0_0, _da0_1)); });
    fr.v1 = {f_kind:{tag:0,p0:{}},f_target:0n,f_data:{tag:0,p0:{}}};
    fr.v1.f_kind = {tag:5};
    fr.v1.f_target = 0n;
    fr.v1.f_data = {tag:2,p2:{f_f0:fr.p_n}};
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 1;
    _p = rt.rt_send_poll(o_g_gui_g_sess.f_events, fr.v1, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 1:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    (rt.rt_sset(fr.v0, 1n));
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_send_event(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    fr.v0 = o_f_gui_cell_take();
    const _da0_0 = fr.v0;
    const _da0_1 = 1n;
    rt.rt_defer_push(() => { (o_f_gui_credit_unless(_da0_0, _da0_1)); });
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 1;
    _p = rt.rt_send_poll(o_g_gui_g_sess.f_events, fr.p_e, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 1:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    (rt.rt_sset(fr.v0, 1n));
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_dispatch_loop(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    case 1:
    if (!((1n === 1n))) { fr.state = 2; continue dispatch; }
    fr.v0 = (() => { rt.rt_borrow_mut(o_g_gui_g_eb); const __rc = o_f_gui_EventBuf_take_dp(o_g_gui_g_eb); rt.rt_unborrow(o_g_gui_g_eb); return __rc; })();
    if (!((fr.v0 > 0n))) { fr.state = 3; continue dispatch; }
    { const _c4 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c4.p_n = fr.v0;
      fr.child = _c4; fr.state = 4; }
    case 4:
      _p = o_poll_gui_send_marked(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.child = null;
    fr.state = 3; continue dispatch;
    case 3:
    fr.v1 = (() => { rt.rt_borrow_mut(o_g_gui_g_eb); const __rc = o_f_gui_EventBuf_pop(o_g_gui_g_eb); rt.rt_unborrow(o_g_gui_g_eb); return __rc; })();
    if (!((fr.v1 === null || fr.v1 === 0n))) { fr.state = 5; continue dispatch; }
    if (!(((() => { rt.rt_borrow_mut(o_g_gui_g_eb); const __rc = o_f_gui_EventBuf_closed_empty(o_g_gui_g_eb); rt.rt_unborrow(o_g_gui_g_eb); return __rc; })() === 1n))) { fr.state = 6; continue dispatch; }
    (rt.rt_try_send(o_g_gui_g_sess.f_done, 1n));
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 6; continue dispatch;
    case 6:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 7;
    _p = rt.rt_recv_poll(o_g_gui_g_eb.f_ping, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 7:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 1; continue dispatch;
    fr.state = 5; continue dispatch;
    case 5:
    { const _c8 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c8.p_e = fr.v1;
      fr.child = _c8; fr.state = 8; }
    case 8:
      _p = o_poll_gui_send_event(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.child = null;
    fr.state = 1; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_watcher(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    rt.rt_defer_push(() => { (((_iv) => _iv.methods.stop(_iv.obj))(fr.p_b)); });
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 1;
    _p = rt.rt_recv_poll(fr.p_rt, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 1:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_pump_task(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    fr.v0 = ((_iv) => _iv.methods.pump_edge(_iv.obj))(fr.p_b);
    case 1:
    if (!((1n === 1n))) { fr.state = 2; continue dispatch; }
    fr.v1 = ((_iv) => _iv.methods.pump_iter(_iv.obj, fr.p_events, fr.p_cmds))(fr.p_b);
    if (!((((_iv) => _iv.methods.stopped(_iv.obj))(fr.p_b) === 1n))) { fr.state = 3; continue dispatch; }
    fr.state = 2; continue dispatch;
    fr.state = 3; continue dispatch;
    case 3:
    if (!(((fr.v1 === 0n) && (o_f_gui_CmdBuf_take_wake(fr.p_cmds) === 0n)))) { fr.state = 4; continue dispatch; }
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 5;
    { const _sc5 = [fr.v0];
      _p = rt.rt_select_poll(_sc5, 1, 50n, 0, t);
      if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; } }
    case 5:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    { const _a5 = rt.rt_select_arm(t);
      if (_a5 === 0n) { fr.state = 7; continue dispatch; }
      if (_a5 === rt.RT_SEL_TMO) { fr.state = 8; continue dispatch; }
      fr.state = 6; continue dispatch; }
    case 7:
    fr.state = 6; continue dispatch;
    case 8:
    fr.state = 6; continue dispatch;
    case 6:
    fr.state = 4; continue dispatch;
    case 4:
    fr.state = 1; continue dispatch;
    case 2:
    (((_iv) => _iv.methods.pump_fin(_iv.obj))(fr.p_b));
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_run(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    if (!((!rt.rt_is_root()))) { fr.state = 1; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = o_f_gui_err_not_root();
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 1; continue dispatch;
    case 1:
    if (!((o_g_gui_g_running === 1n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = o_f_errors_new(rt.rt_str_lit("Z3VpOiBhbHJlYWR5IHJ1bm5pbmc="));
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    o_g_gui_g_running = 1n;
    (o_f_gui_last_dropped_cell());
    o_g_gui_g_eb = {f_mu:null,f_closed:null,f_dropped:null,f_dp:null,f_ping:null,f_cap:0n,f_elig:0n,f_q:null,f_wt:null,f_strs:null};
    o_g_gui_g_eb.f_mu = o_f_sync_mutex();
    o_g_gui_g_eb.f_closed = rt.rt_mkshared(0n);
    o_g_gui_g_eb.f_dropped = rt.rt_mkshared(0n);
    o_g_gui_g_eb.f_dp = rt.rt_mkshared(0n);
    o_g_gui_g_eb.f_ping = rt.rt_mkchan_scoped(null, 1n, null);
    o_g_gui_g_eb.f_cap = o_g_gui_g_event_cap;
    o_g_gui_g_eb.f_elig = 0n;
    o_g_gui_g_eb.f_q = null;
    o_g_gui_g_eb.f_wt = null;
    o_g_gui_g_eb.f_strs = null;
    o_g_gui_g_cb = {f_mu:null,f_closed:null,f_room:null,f_cap:0n,f_len:0n,f_q:null,f_strs:null,f_wakep:null};
    o_g_gui_g_cb.f_mu = o_f_sync_mutex();
    o_g_gui_g_cb.f_closed = rt.rt_mkshared(0n);
    o_g_gui_g_cb.f_room = rt.rt_mkchan_scoped(null, o_g_gui_g_cmd_cap, null);
    o_g_gui_g_cb.f_cap = o_g_gui_g_cmd_cap;
    o_g_gui_g_cb.f_len = 0n;
    o_g_gui_g_cb.f_q = null;
    o_g_gui_g_cb.f_strs = null;
    o_g_gui_g_cb.f_wakep = rt.rt_mkshared(0n);
    fr.v0 = rt.rt_mkchan_scoped(rt.rt_scope_current(), o_g_gui_g_event_cap, o_drop_word);
    o_g_gui_g_sess = {f_b:null,f_events:null,f_done:null,f_retire:null,f_mscope:null,f_disp:null};
    o_g_gui_g_sess.f_b = fr.p_b;
    o_g_gui_g_sess.f_events = fr.v0;
    o_g_gui_g_sess.f_done = rt.rt_mkchan_scoped(null, 1n, null);
    o_g_gui_g_sess.f_retire = rt.rt_mkchan_scoped(null, 1n, null);
    o_g_gui_g_sess.f_mscope = rt.rt_scope_current();
    o_g_gui_g_rp = null;
    o_g_gui_g_rp_n = 0n;
    o_g_gui_g_rp_mu = o_f_sync_mutex();
    o_g_gui_g_cells = null;
    o_g_gui_g_cells_n = 0n;
    o_g_gui_g_cell_mu = o_f_sync_mutex();
    { const _t3 = o_frm_gui_watcher();
      _t3.p_b = fr.p_b;
      _t3.p_rt = o_g_gui_g_sess.f_retire;
      rt.rt_spawn_task(_t3); }
    fr.sc0 = rt.rt_scope_make(); rt.rt_scope_enter(fr.sc0);
    fr.v1 = rt.rt_scope_named();
    o_g_gui_g_sess.f_disp = fr.v1;
    { const _t4 = rt.rt_task_new_in(fr.v1, o_poll_gui_dispatch_loop);
      rt.rt_spawn_task(_t4); }
    (fr.p_app(fr.v0));
    if (!((((_iv) => _iv.methods.susp_pump(_iv.obj))(o_g_gui_g_sess.f_b) === 1n))) { fr.state = 3; continue dispatch; }
    { const _c5 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c5.p_b = o_g_gui_g_sess.f_b;
      _c5.p_events = o_g_gui_g_eb;
      _c5.p_cmds = o_g_gui_g_cb;
      fr.child = _c5; fr.state = 5; }
    case 5:
      _p = o_poll_gui_pump_task(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.child = null;
    fr.state = 4; continue dispatch;
    case 3:
    (((_iv) => _iv.methods.pump(_iv.obj, o_g_gui_g_eb, o_g_gui_g_cb))(o_g_gui_g_sess.f_b));
    fr.state = 4; continue dispatch;
    case 4:
    (rt.rt_close(o_g_gui_g_sess.f_retire));
    (o_f_gui_cb_shutdown());
    (o_f_sync_mlock(o_g_gui_g_eb.f_mu));
    (rt.rt_sset(o_g_gui_g_eb.f_closed, 1n));
    (o_f_sync_munlock(o_g_gui_g_eb.f_mu));
    (rt.rt_try_send(o_g_gui_g_eb.f_ping, 1n));
    fr.v2 = o_g_gui_g_drain_ms;
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 6;
    { const _sc6 = [o_g_gui_g_sess.f_done];
      _p = rt.rt_select_poll(_sc6, 1, fr.v2, 0, t);
      if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; } }
    case 6:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    { const _a6 = rt.rt_select_arm(t);
      if (_a6 === 0n) { fr.state = 8; continue dispatch; }
      if (_a6 === rt.RT_SEL_TMO) { fr.state = 9; continue dispatch; }
      fr.state = 7; continue dispatch; }
    case 8:
    fr.state = 7; continue dispatch;
    case 9:
    (rt.rt_scope_cancel(fr.v1));
    fr.state = 7; continue dispatch;
    case 7:
    fr.state = 10;
    _p = rt.rt_scope_join_poll(fr.v1, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 10:
    rt.rt_scope_finish_named(fr.v1);
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    (o_f_gui_eb_count_rest());
    fr.v3 = (() => { rt.rt_borrow_mut(o_g_gui_g_eb); const __rc = o_f_gui_EventBuf_take_dp(o_g_gui_g_eb); rt.rt_unborrow(o_g_gui_g_eb); return __rc; })();
    if (!((fr.v3 > 0n))) { fr.state = 11; continue dispatch; }
    fr.v4 = {f_kind:{tag:0,p0:{}},f_target:0n,f_data:{tag:0,p0:{}}};
    fr.v4.f_kind = {tag:5};
    fr.v4.f_target = 0n;
    fr.v4.f_data = {tag:2,p2:{f_f0:fr.v3}};
    (rt.rt_try_send(fr.v0, fr.v4));
    fr.state = 11; continue dispatch;
    case 11:
    (rt.rt_close(fr.v0));
    fr.state = 12;
    _p = rt.rt_scope_join_poll(fr.sc0, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 12:
    { const _e12 = rt.rt_scope_finish(fr.sc0);
      if (_e12) rt.rt_scope_propagate(rt.rt_scope_current(), _e12); }
    (rt.rt_sset(o_g_gui_g_last_dropped, rt.rt_sget(o_g_gui_g_eb.f_dropped)));
    ((() => { rt.rt_borrow_mut(o_g_gui_g_cb); o_f_gui_CmdBuf_free_strs(o_g_gui_g_cb); rt.rt_unborrow(o_g_gui_g_cb); })());
    ((() => { rt.rt_borrow_mut(o_g_gui_g_eb); o_f_gui_EventBuf_free_strs(o_g_gui_g_eb); rt.rt_unborrow(o_g_gui_g_eb); })());
    o_g_gui_g_running = 0n;
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = null;
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_create(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    if (!((o_g_gui_g_cb === null || o_g_gui_g_cb === 0n))) { fr.state = 1; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: 0n, err: o_f_gui_err_stopped()};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 1; continue dispatch;
    case 1:
    fr.v0 = o_f_gui_reply_chan();
    fr.v1 = o_f_gui_cell_take();
    const _da0_0 = fr.v0;
    const _da0_1 = fr.v1;
    rt.rt_defer_push(() => { (o_f_gui_reply_done(_da0_0, _da0_1)); });
    fr.v2 = o_f_gui_mk_cmd({tag:0}, fr.p_parent, 0n);
    fr.v2.f_widget = fr.p_kind;
    fr.v2.f_props = fr.p_props;
    fr.v2.f_reply = fr.v0;
    fr.v3 = o_f_gui_post_reply(fr.v2);
    if (!((fr.v3 !== null && fr.v3 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: 0n, err: fr.v3};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 3;
    _p = rt.rt_recv_poll(fr.v0, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 3:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.v4 = (rt.rt_task_data(t) === null ? null : rt.rt_task_data(t));
    if (!((fr.v4 === null || fr.v4 === 0n))) { fr.state = 4; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: 0n, err: o_f_gui_err_stopped()};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 4; continue dispatch;
    case 4:
    (rt.rt_sset(fr.v1, 1n));
    if (!((fr.v4.f_e !== null && fr.v4.f_e !== 0n))) { fr.state = 5; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: 0n, err: fr.v4.f_e};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 5; continue dispatch;
    case 5:
    fr.v5 = fr.v4.f_handle;
    (o_f_sync_mlock(o_g_gui_g_eb.f_mu));
    o_g_gui_g_eb.f_wt = o_f_gui_wt_put(o_g_gui_g_eb.f_wt, fr.v5, o_f_gui_kind_i(fr.p_kind));
    if (!((fr.p_parent !== 0n))) { fr.state = 6; continue dispatch; }
    o_g_gui_g_eb.f_wt = o_f_gui_wt_set(o_g_gui_g_eb.f_wt, fr.v5, 3n, fr.p_parent);
    fr.state = 6; continue dispatch;
    case 6:
    (o_f_sync_munlock(o_g_gui_g_eb.f_mu));
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: fr.v5, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_window(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:0};
      _c1.p_parent = 0n;
      _c1.p_props = o_f_gui_props1(o_g_gui_P_TITLE, {tag:0,p0:{f_f0:fr.p_title}});
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_vbox(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:1};
      _c1.p_parent = 0n;
      _c1.p_props = null;
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_hbox(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:2};
      _c1.p_parent = 0n;
      _c1.p_props = null;
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_label(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:3};
      _c1.p_parent = 0n;
      _c1.p_props = o_f_gui_props1(o_g_gui_P_TEXT, {tag:0,p0:{f_f0:fr.p_text}});
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_button(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:4};
      _c1.p_parent = 0n;
      _c1.p_props = o_f_gui_props1(o_g_gui_P_TEXT, {tag:0,p0:{f_f0:fr.p_text}});
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_entry(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:5};
      _c1.p_parent = 0n;
      _c1.p_props = o_f_gui_props1(o_g_gui_P_PLACEHOLDER, {tag:0,p0:{f_f0:fr.p_placeholder}});
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_list(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:6};
      _c1.p_parent = 0n;
      _c1.p_props = null;
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_scrolled(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_kind = {tag:7};
      _c1.p_parent = 0n;
      _c1.p_props = null;
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_create(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:0n}, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {f_h:fr.v0}, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_read_prop(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    if (!((o_g_gui_g_cb === null || o_g_gui_g_cb === 0n))) { fr.state = 1; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {tag:2,p2:{f_f0:0n}}, err: o_f_gui_err_stopped()};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 1; continue dispatch;
    case 1:
    fr.v0 = o_f_gui_reply_chan();
    fr.v1 = o_f_gui_cell_take();
    const _da0_0 = fr.v0;
    const _da0_1 = fr.v1;
    rt.rt_defer_push(() => { (o_f_gui_reply_done(_da0_0, _da0_1)); });
    fr.v2 = o_f_gui_mk_cmd({tag:5}, fr.p_h, 0n);
    fr.v2.f_prop = {f_id:fr.p_id,f_val:{tag:2,p2:{f_f0:0n}}};
    fr.v2.f_reply = fr.v0;
    fr.v3 = o_f_gui_post_reply(fr.v2);
    if (!((fr.v3 !== null && fr.v3 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {tag:2,p2:{f_f0:0n}}, err: fr.v3};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 3;
    _p = rt.rt_recv_poll(fr.v0, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 3:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.v4 = (rt.rt_task_data(t) === null ? null : rt.rt_task_data(t));
    if (!((fr.v4 === null || fr.v4 === 0n))) { fr.state = 4; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {tag:2,p2:{f_f0:0n}}, err: o_f_gui_err_stopped()};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 4; continue dispatch;
    case 4:
    (rt.rt_sset(fr.v1, 1n));
    if (!((fr.v4.f_e !== null && fr.v4.f_e !== 0n))) { fr.state = 5; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: {tag:2,p2:{f_f0:0n}}, err: fr.v4.f_e};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 5; continue dispatch;
    case 5:
    fr.v5 = fr.v4.f_val;
    if (fr.v5.tag === 0) { fr.state = 7; continue dispatch; }
    fr.state = 8; continue dispatch;
    fr.state = 6; continue dispatch;
    case 7:
      fr.v6 = fr.v5.p0.f_f0;
    fr.v4.f_val = {tag:0,p0:{f_f0:globalThis.__oxl_ffi.rt_str_scope(fr.v6)}};
    (globalThis.__oxl_ffi.rt_str_free(fr.v6));
    fr.state = 6; continue dispatch;
    case 8:
    fr.state = 6; continue dispatch;
    case 6:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: fr.v4.f_val, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_Entry_text(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_h = fr.p_e.f_h;
      _c1.p_id = o_g_gui_P_TEXT;
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_read_prop(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: rt.rt_str_lit(""), err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    fr.v2 = fr.v0;
    if (fr.v2.tag === 0) { fr.state = 4; continue dispatch; }
    if (fr.v2.tag === 1) { fr.state = 5; continue dispatch; }
    if (fr.v2.tag === 2) { fr.state = 6; continue dispatch; }
    fr.state = 3; continue dispatch;
    case 4:
      fr.v3 = fr.v2.p0.f_f0;
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: fr.v3, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 3; continue dispatch;
    case 5:
      fr.v4 = fr.v2.p1.f_f0;
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: rt.rt_str_lit(""), err: o_f_gui_err_gone()};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 3; continue dispatch;
    case 6:
      fr.v5 = fr.v2.p2.f_f0;
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: rt.rt_str_lit(""), err: o_f_gui_err_gone()};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 3; continue dispatch;
    case 3:
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_gui_List_rows(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_h = fr.p_l.f_h;
      _c1.p_id = o_g_gui_P_ROWS;
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_read_prop(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    if (!((fr.v1 !== null && fr.v1 !== 0n))) { fr.state = 2; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: 0n, err: fr.v1};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    fr.v2 = fr.v0;
    if (fr.v2.tag === 2) { fr.state = 4; continue dispatch; }
    fr.state = 5; continue dispatch;
    fr.state = 3; continue dispatch;
    case 4:
      fr.v3 = fr.v2.p2.f_f0;
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: fr.v3, err: null};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 3; continue dispatch;
    case 5:
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = {val: 0n, err: o_f_errors_new(rt.rt_str_lit("Z3VpOiB1bmV4cGVjdGVkIFBfUk9XUyBwYXlsb2Fk"))};
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 3; continue dispatch;
    case 3:
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_time_sleep_ms(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 1;
    _p = rt.rt_msleep_poll(fr.p_ms, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 1:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_add_row(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_hbox(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    { const _c2 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c2.p_text = fr.p_text;
      fr.child = _c2; fr.state = 2; }
    case 2:
      _p = o_poll_gui_label(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r2 = fr.child.result;
        fr.v2 = _r2.val;
        fr.v3 = _r2.err;
      }
      fr.child = null;
    { const _c3 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c3.p_text = rt.rt_str_lit("eA==");
      fr.child = _c3; fr.state = 3; }
    case 3:
      _p = o_poll_gui_button(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r3 = fr.child.result;
        fr.v4 = _r3.val;
        fr.v5 = _r3.err;
      }
      fr.child = null;
    if (!((((fr.v1 !== null && fr.v1 !== 0n) || (fr.v3 !== null && fr.v3 !== 0n)) || (fr.v5 !== null && fr.v5 !== 0n)))) { fr.state = 4; continue dispatch; }
    (rt.rt_println_str(rt.rt_str_lit("cm93IGNyZWF0ZSBmYWlsZWQ=")));
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = 0n;
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 4; continue dispatch;
    case 4:
    (o_f_gui_append({obj: Object.assign({}, fr.v0), methods: o_vt_gui_Widget_gui_HBox}, {obj: Object.assign({}, fr.v2), methods: o_vt_gui_Widget_gui_Label}));
    (o_f_gui_append({obj: Object.assign({}, fr.v0), methods: o_vt_gui_Widget_gui_HBox}, {obj: Object.assign({}, fr.v4), methods: o_vt_gui_Widget_gui_Button}));
    (o_f_gui_append({obj: Object.assign({}, fr.p_lb), methods: o_vt_gui_Widget_gui_List}, {obj: Object.assign({}, fr.v0), methods: o_vt_gui_Widget_gui_HBox}));
    (o_f_row_put(o_f_gui_Button_handle(fr.v4), o_f_gui_HBox_handle(fr.v0)));
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = o_f_gui_Button_handle(fr.v4);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_wait_rows(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    fr.v0 = 0n;
    case 1:
    if (!((fr.v0 < 4000n))) { fr.state = 2; continue dispatch; }
    { const _c3 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c3.p_l = o_g_g_lb;
      fr.child = _c3; fr.state = 3; }
    case 3:
      _p = o_poll_gui_List_rows(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r3 = fr.child.result;
        fr.v1 = _r3.val;
        fr.v2 = _r3.err;
      }
      fr.child = null;
    if (!(((fr.v2 === null || fr.v2 === 0n) && (fr.v1 === fr.p_want)))) { fr.state = 4; continue dispatch; }
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = 1n;
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 4; continue dispatch;
    case 4:
    { const _c5 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c5.p_ms = 5n;
      fr.child = _c5; fr.state = 5; }
    case 5:
      _p = o_poll_time_sleep_ms(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.child = null;
    fr.v0 = rt.rt_iadd(fr.v0, 1n);
    fr.state = 1; continue dispatch;
    case 2:
    (rt.rt_println_str(rt.rt_strcat(rt.rt_strcat(rt.rt_strcat(rt.rt_strcat(rt.rt_strcat(rt.rt_str_lit("c2VsZnRlc3Q6IHJvd3MgbmV2ZXIgcmVhY2hlZCBoYj0="), rt.rt_itoa(o_f_sync_cval(o_g_g_hb))), rt.rt_str_lit("IHJtPQ==")), rt.rt_itoa(o_f_sync_cval(o_g_g_rm))), rt.rt_str_lit("IGRyb3BwZWQ9")), rt.rt_itoa(o_f_gui_events_dropped()))));
    rt.rt_defer_drain_to(fr._dmark);
    fr.result = 0n;
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_selftest_drive(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    (o_f_gui_Entry_set_text(o_g_g_en, rt.rt_str_lit("b25l")));
    (o_f_dom_Dom_fire(o_g_g_d, o_f_gui_Button_handle(o_g_g_add), o_g_dom_D_CLICK));
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_want = 1n;
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_wait_rows(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v0 = fr.child.result;
      fr.child = null;
    if (!((fr.v0 === 0n))) { fr.state = 2; continue dispatch; }
    (o_f_gui_stop());
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 2; continue dispatch;
    case 2:
    (o_f_gui_Entry_set_text(o_g_g_en, rt.rt_str_lit("dHdv")));
    (o_f_dom_Dom_fire(o_g_g_d, o_f_gui_Button_handle(o_g_g_add), o_g_dom_D_CLICK));
    { const _c3 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c3.p_want = 2n;
      fr.child = _c3; fr.state = 3; }
    case 3:
      _p = o_poll_wait_rows(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v1 = fr.child.result;
      fr.child = null;
    if (!((fr.v1 === 0n))) { fr.state = 4; continue dispatch; }
    (o_f_gui_stop());
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 4; continue dispatch;
    case 4:
    { const _c5 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c5.p_lb = o_g_g_lb;
      _c5.p_text = rt.rt_str_lit("ZG9vbWVk");
      fr.child = _c5; fr.state = 5; }
    case 5:
      _p = o_poll_add_row(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v2 = fr.child.result;
      fr.child = null;
    { const _c6 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c6.p_want = 3n;
      fr.child = _c6; fr.state = 6; }
    case 6:
      _p = o_poll_wait_rows(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v3 = fr.child.result;
      fr.child = null;
    if (!((fr.v3 === 0n))) { fr.state = 7; continue dispatch; }
    (o_f_gui_stop());
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 7; continue dispatch;
    case 7:
    (o_f_dom_Dom_fire(o_g_g_d, fr.v2, o_g_dom_D_CLICK));
    { const _c8 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c8.p_want = 2n;
      fr.child = _c8; fr.state = 8; }
    case 8:
      _p = o_poll_wait_rows(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v4 = fr.child.result;
      fr.child = null;
    if (!((fr.v4 === 0n))) { fr.state = 9; continue dispatch; }
    (o_f_gui_stop());
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 9; continue dispatch;
    case 9:
    fr.v5 = 200n;
    if (!((rt.rt_argc() > 2n))) { fr.state = 10; continue dispatch; }
    fr.v5 = rt.rt_atoi(rt.rt_argv(2n));
    fr.state = 10; continue dispatch;
    case 10:
    fr.v6 = 0n;
    case 11:
    if (!((fr.v6 < fr.v5))) { fr.state = 12; continue dispatch; }
    { const _c13 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c13.p_lb = o_g_g_lb;
      _c13.p_text = rt.rt_str_lit("Y2h1cm4=");
      fr.child = _c13; fr.state = 13; }
    case 13:
      _p = o_poll_add_row(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v7 = fr.child.result;
      fr.child = null;
    (o_f_dom_Dom_fire(o_g_g_d, fr.v7, o_g_dom_D_CLICK));
    fr.v6 = rt.rt_iadd(fr.v6, 1n);
    fr.state = 11; continue dispatch;
    case 12:
    { const _c14 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c14.p_want = 2n;
      fr.child = _c14; fr.state = 14; }
    case 14:
      _p = o_poll_wait_rows(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v8 = fr.child.result;
      fr.child = null;
    if (!((fr.v8 === 0n))) { fr.state = 15; continue dispatch; }
    (o_f_gui_stop());
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 15; continue dispatch;
    case 15:
    (rt.rt_println_str(rt.rt_strcat(rt.rt_strcat(rt.rt_str_lit("c2VsZnRlc3Qgcm93cz0yIGNodXJuPQ=="), rt.rt_itoa(fr.v5)), rt.rt_str_lit("IG9r"))));
    (o_f_gui_stop());
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_ui(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    { const _c1 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c1.p_title = rt.rt_str_lit("b3hsIHRvZG8=");
      fr.child = _c1; fr.state = 1; }
    case 1:
      _p = o_poll_gui_window(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r1 = fr.child.result;
        fr.v0 = _r1.val;
        fr.v1 = _r1.err;
      }
      fr.child = null;
    { const _c2 = {cur_scope: rt.rt_scope_current(), state: 0};
      fr.child = _c2; fr.state = 2; }
    case 2:
      _p = o_poll_gui_vbox(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r2 = fr.child.result;
        fr.v2 = _r2.val;
        fr.v3 = _r2.err;
      }
      fr.child = null;
    { const _c3 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c3.p_placeholder = rt.rt_str_lit("");
      fr.child = _c3; fr.state = 3; }
    case 3:
      _p = o_poll_gui_entry(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r3 = fr.child.result;
        fr.v4 = _r3.val;
        fr.v5 = _r3.err;
      }
      fr.child = null;
    { const _c4 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c4.p_text = rt.rt_str_lit("YWRk");
      fr.child = _c4; fr.state = 4; }
    case 4:
      _p = o_poll_gui_button(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r4 = fr.child.result;
        fr.v6 = _r4.val;
        fr.v7 = _r4.err;
      }
      fr.child = null;
    { const _c5 = {cur_scope: rt.rt_scope_current(), state: 0};
      fr.child = _c5; fr.state = 5; }
    case 5:
      _p = o_poll_gui_list(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r5 = fr.child.result;
        fr.v8 = _r5.val;
        fr.v9 = _r5.err;
      }
      fr.child = null;
    { const _c6 = {cur_scope: rt.rt_scope_current(), state: 0};
      fr.child = _c6; fr.state = 6; }
    case 6:
      _p = o_poll_gui_scrolled(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r6 = fr.child.result;
        fr.v10 = _r6.val;
        fr.v11 = _r6.err;
      }
      fr.child = null;
    if (!(((((((fr.v1 !== null && fr.v1 !== 0n) || (fr.v3 !== null && fr.v3 !== 0n)) || (fr.v5 !== null && fr.v5 !== 0n)) || (fr.v7 !== null && fr.v7 !== 0n)) || (fr.v9 !== null && fr.v9 !== 0n)) || (fr.v11 !== null && fr.v11 !== 0n)))) { fr.state = 7; continue dispatch; }
    (rt.rt_println_str(rt.rt_str_lit("dWkgY3JlYXRlIGZhaWxlZA==")));
    (o_f_gui_stop());
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    fr.state = 7; continue dispatch;
    case 7:
    o_g_g_lb = fr.v8;
    o_g_g_en = fr.v4;
    o_g_g_add = fr.v6;
    (o_f_gui_append({obj: Object.assign({}, fr.v10), methods: o_vt_gui_Widget_gui_Scrolled}, {obj: Object.assign({}, fr.v8), methods: o_vt_gui_Widget_gui_List}));
    (o_f_gui_append({obj: Object.assign({}, fr.v2), methods: o_vt_gui_Widget_gui_VBox}, {obj: Object.assign({}, fr.v4), methods: o_vt_gui_Widget_gui_Entry}));
    (o_f_gui_append({obj: Object.assign({}, fr.v2), methods: o_vt_gui_Widget_gui_VBox}, {obj: Object.assign({}, fr.v6), methods: o_vt_gui_Widget_gui_Button}));
    (o_f_gui_append({obj: Object.assign({}, fr.v2), methods: o_vt_gui_Widget_gui_VBox}, {obj: Object.assign({}, fr.v10), methods: o_vt_gui_Widget_gui_Scrolled}));
    (o_f_gui_append({obj: Object.assign({}, fr.v0), methods: o_vt_gui_Widget_gui_Window}, {obj: Object.assign({}, fr.v2), methods: o_vt_gui_Widget_gui_VBox}));
    if (!((o_g_g_selftest === 1n))) { fr.state = 8; continue dispatch; }
    { const _t11 = o_frm_selftest_drive();
      rt.rt_spawn_task(_t11); }
    fr.state = 8; continue dispatch;
    case 8:
    case 9:
    if (!((1n === 1n))) { fr.state = 10; continue dispatch; }
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.state = 11;
    _p = rt.rt_recv_poll(fr.p_events, t);
    if (_p === rt.RT_PENDING) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_PENDING; }
    case 11:
    if (rt.rt_cancelled()) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_CANCEL; }
    fr.v12 = (rt.rt_task_data(t) === null ? null : rt.rt_task_data(t));
    if (!((fr.v12 === null || fr.v12 === 0n))) { fr.state = 12; continue dispatch; }
    fr.state = 10; continue dispatch;
    fr.state = 12; continue dispatch;
    case 12:
    (o_f_sync_cinc(o_g_g_hb));
    if (!((fr.v12.f_kind.tag === {tag:0}.tag))) { fr.state = 13; continue dispatch; }
    if (!((fr.v12.f_target === o_f_gui_Button_handle(fr.v6)))) { fr.state = 14; continue dispatch; }
    { const _c16 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c16.p_e = fr.v4;
      fr.child = _c16; fr.state = 16; }
    case 16:
      _p = o_poll_gui_Entry_text(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r16 = fr.child.result;
        fr.v13 = _r16.val;
        fr.v14 = _r16.err;
      }
      fr.child = null;
    if (!(((fr.v14 === null || fr.v14 === 0n) && (rt.rt_len(fr.v13) > 0n)))) { fr.state = 17; continue dispatch; }
    { const _c18 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c18.p_lb = fr.v8;
      _c18.p_text = fr.v13;
      fr.child = _c18; fr.state = 18; }
    case 18:
      _p = o_poll_add_row(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.child = null;
    (o_f_gui_Entry_set_text(fr.v4, rt.rt_str_lit("")));
    fr.state = 17; continue dispatch;
    case 17:
    fr.state = 15; continue dispatch;
    case 14:
    fr.v15 = o_f_row_take(fr.v12.f_target);
    if (!((fr.v15 !== 0n))) { fr.state = 19; continue dispatch; }
    (o_f_sync_cinc(o_g_g_rm));
    (o_f_gui_remove({obj: Object.assign({}, {f_h:fr.v15}), methods: o_vt_gui_Widget_gui_HBox}));
    fr.state = 19; continue dispatch;
    case 19:
    fr.state = 15; continue dispatch;
    case 15:
    fr.state = 13; continue dispatch;
    case 13:
    if (!(((fr.v12.f_kind.tag === {tag:1}.tag) && (fr.v12.f_target === o_f_gui_Entry_handle(fr.v4))))) { fr.state = 20; continue dispatch; }
    { const _c21 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c21.p_e = fr.v4;
      fr.child = _c21; fr.state = 21; }
    case 21:
      _p = o_poll_gui_Entry_text(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      { const _r21 = fr.child.result;
        fr.v16 = _r21.val;
        fr.v17 = _r21.err;
      }
      fr.child = null;
    if (!(((fr.v17 === null || fr.v17 === 0n) && (rt.rt_len(fr.v16) > 0n)))) { fr.state = 22; continue dispatch; }
    { const _c23 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c23.p_lb = fr.v8;
      _c23.p_text = fr.v16;
      fr.child = _c23; fr.state = 23; }
    case 23:
      _p = o_poll_add_row(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.child = null;
    (o_f_gui_Entry_set_text(fr.v4, rt.rt_str_lit("")));
    fr.state = 22; continue dispatch;
    case 22:
    fr.state = 20; continue dispatch;
    case 20:
    if (!(((fr.v12.f_kind.tag === {tag:3}.tag) && (fr.v12.f_target === o_f_gui_Window_handle(fr.v0))))) { fr.state = 24; continue dispatch; }
    (o_f_gui_stop());
    fr.state = 24; continue dispatch;
    case 24:
    fr.state = 9; continue dispatch;
    case 10:
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_poll_main(fr, t) {
    const saved = rt.rt_scope_current();
    rt.rt_scope_set(fr.cur_scope);
    let _p;
    dispatch: for (;;) {
    switch (fr.state) {
    case 0:
      fr._dmark = rt.rt_defer_mark();
    if (!(((rt.rt_argc() > 1n) && (rt.rt_streq(rt.rt_argv(1n), rt.rt_str_lit("LS1zZWxmdGVzdA==")))))) { fr.state = 1; continue dispatch; }
    o_g_g_selftest = 1n;
    fr.state = 1; continue dispatch;
    case 1:
    { const _c2 = {cur_scope: rt.rt_scope_current(), state: 0};
      _c2.p_b = {obj: Object.assign({}, o_g_g_d), methods: o_vt_gui_Backend_dom_Dom};
      _c2.p_app = o_f_app;
      fr.child = _c2; fr.state = 2; }
    case 2:
      _p = o_poll_gui_run(fr.child, t);
      if (_p !== rt.RT_READY) { fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return _p; }
      fr.v0 = fr.child.result;
      fr.child = null;
    if (!((fr.v0 !== null && fr.v0 !== 0n))) { fr.state = 3; continue dispatch; }
    (rt.rt_println_str(rt.rt_strcat(rt.rt_str_lit("cnVuOiA="), o_f_errors_msg(fr.v0))));
    (globalThis.__oxl_ffi.rt_exit(1n));
    fr.state = 3; continue dispatch;
    case 3:
    (rt.rt_println_str(rt.rt_str_lit("Z3VpIGRvbmU=")));
    rt.rt_defer_drain_to(fr._dmark);
    fr.cur_scope = rt.rt_scope_current(); rt.rt_scope_set(saved); return rt.RT_READY;
    default:
      rt.rt_scope_set(saved); return rt.RT_READY;
    }
    }
}
function o_f_errors_new(msg) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return globalThis.__oxl_ffi.rt_err_new(msg);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_errors_msg(e) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return globalThis.__oxl_ffi.rt_err_msg(e);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_sync_mutex() {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_mkshared(0n);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_sync_mlock(m) {
    const _dmark = rt.rt_defer_mark();
    while ((rt.rt_scas(m, 0n, 1n) !== 0n)) {
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_sync_munlock(m) {
    const _dmark = rt.rt_defer_mark();
    (rt.rt_sset(m, 0n));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_sync_counter() {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_mkshared(0n);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_sync_cinc(c) {
    const _dmark = rt.rt_defer_mark();
    (rt.rt_sadd(c, 1n));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_sync_cval(c) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_sget(c);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_err_not_root() {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return o_f_errors_new(rt.rt_str_lit("Z3VpOiByb290IHRhc2sgcmVxdWlyZWQ="));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_err_stopped() {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return o_f_errors_new(rt.rt_str_lit("Z3VpOiBiYWNrZW5kIHN0b3BwZWQ="));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_err_gone() {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return o_f_errors_new(rt.rt_str_lit("Z3VpOiB3aWRnZXQgZ29uZQ=="));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_en_cons(v, elig, next) {
    const _dmark = rt.rt_defer_mark();
    let c = {f_v:null,f_elig:0n,f_next:null};
    c.f_v = v;
    c.f_elig = elig;
    c.f_next = next;
    rt.rt_defer_drain_to(_dmark);
    return c;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_en_rm_last(l) {
    const _dmark = rt.rt_defer_mark();
    let r = {f_list:null,f_found:null};
    if ((l === null || l === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return r;
    }
    if ((l.f_next === null || l.f_next === 0n)) {
    r.f_found = l;
    rt.rt_defer_drain_to(_dmark);
    return r;
    }
    let rest = l.f_next;
    l.f_next = null;
    let rr = o_f_gui_en_rm_last(rest);
    l.f_next = rr.f_list;
    r.f_list = l;
    r.f_found = rr.f_found;
    rt.rt_defer_drain_to(_dmark);
    return r;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_en_rm_last_elig(l) {
    const _dmark = rt.rt_defer_mark();
    let r = {f_list:null,f_found:null};
    if ((l === null || l === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return r;
    }
    let rest = l.f_next;
    l.f_next = null;
    let rr = o_f_gui_en_rm_last_elig(rest);
    if (((rr.f_found === null || rr.f_found === 0n) && (l.f_elig === 1n))) {
    l.f_next = null;
    r.f_list = rr.f_list;
    r.f_found = l;
    rt.rt_defer_drain_to(_dmark);
    return r;
    }
    l.f_next = rr.f_list;
    r.f_list = l;
    r.f_found = rr.f_found;
    rt.rt_defer_drain_to(_dmark);
    return r;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_en_flip_close(b, l, h) {
    const _dmark = rt.rt_defer_mark();
    if ((l === null || l === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return null;
    }
    if ((((l.f_v.f_kind.tag === {tag:3}.tag) && (l.f_v.f_target === h)) && (l.f_elig === 0n))) {
    l.f_elig = 1n;
    b.f_elig = rt.rt_iadd(b.f_elig, 1n);
    }
    l.f_next = o_f_gui_en_flip_close(b, l.f_next, h);
    rt.rt_defer_drain_to(_dmark);
    return l;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_en_len(l) {
    const _dmark = rt.rt_defer_mark();
    let n = 0n;
    while ((l !== null && l !== 0n)) {
    n = rt.rt_iadd(n, 1n);
    l = l.f_next;
    }
    rt.rt_defer_drain_to(_dmark);
    return n;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_wt_get(l, h) {
    const _dmark = rt.rt_defer_mark();
    let r = {f_found:0n,f_alive:0n,f_pend:0n,f_parent:0n};
    while ((l !== null && l !== 0n)) {
    if ((l.f_h === h)) {
    r.f_found = 1n;
    r.f_alive = l.f_alive;
    r.f_pend = l.f_pend;
    r.f_parent = l.f_parent;
    rt.rt_defer_drain_to(_dmark);
    return r;
    }
    l = l.f_next;
    }
    rt.rt_defer_drain_to(_dmark);
    return r;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_wt_set(l, h, which, v) {
    const _dmark = rt.rt_defer_mark();
    if ((l === null || l === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return null;
    }
    if ((l.f_h === h)) {
    if ((which === 1n)) {
    l.f_alive = v;
    }
    if ((which === 2n)) {
    l.f_pend = v;
    }
    if ((which === 3n)) {
    l.f_parent = v;
    }
    rt.rt_defer_drain_to(_dmark);
    return l;
    }
    let rest = l.f_next;
    l.f_next = o_f_gui_wt_set(rest, h, which, v);
    rt.rt_defer_drain_to(_dmark);
    return l;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_wt_put(l, h, kind) {
    const _dmark = rt.rt_defer_mark();
    if ((l === null || l === 0n)) {
    let c = {f_h:0n,f_kind:0n,f_alive:0n,f_pend:0n,f_parent:0n,f_next:null};
    c.f_h = h;
    c.f_kind = kind;
    c.f_alive = 1n;
    c.f_pend = 0n;
    c.f_parent = 0n;
    c.f_next = null;
    rt.rt_defer_drain_to(_dmark);
    return c;
    }
    if ((l.f_h === h)) {
    l.f_alive = 1n;
    l.f_kind = kind;
    rt.rt_defer_drain_to(_dmark);
    return l;
    }
    let rest = l.f_next;
    l.f_next = o_f_gui_wt_put(rest, h, kind);
    rt.rt_defer_drain_to(_dmark);
    return l;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_ev_eligible(b, e) {
    const _dmark = rt.rt_defer_mark();
    if ((e.f_kind.tag === {tag:3}.tag)) {
    let w = (() => { rt.rt_borrow_read(b.f_wt); const __rc = o_f_gui_wt_get(b.f_wt, e.f_target); rt.rt_unborrow(b.f_wt); return __rc; })();
    if ((w.f_alive === 1n)) {
    rt.rt_defer_drain_to(_dmark);
    return 0n;
    }
    }
    rt.rt_defer_drain_to(_dmark);
    return 1n;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_EventBuf_post(b, e) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    if ((rt.rt_sget(b.f_closed) === 1n)) {
    (rt.rt_sset(b.f_dropped, rt.rt_iadd(rt.rt_sget(b.f_dropped), 1n)));
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return 0n;
    }
    if ((e.f_kind.tag === {tag:3}.tag)) {
    let w = (() => { rt.rt_borrow_read(b.f_wt); const __rc = o_f_gui_wt_get(b.f_wt, e.f_target); rt.rt_unborrow(b.f_wt); return __rc; })();
    if ((w.f_alive === 1n)) {
    if ((w.f_pend === 1n)) {
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return 1n;
    }
    b.f_wt = o_f_gui_wt_set(b.f_wt, e.f_target, 2n, 1n);
    }
    }
    { const _ms0 = e.f_data;
      if (_ms0.tag === 1) {
      let t = _ms0.p1.f_f0;
    e.f_data = {tag:1,p1:{f_f0:o_f_gui_eb_intern_l(b, t)}};
      }
      else {
      }
    }
    if (((e.f_kind.tag === {tag:2}.tag) && (b.f_q !== null && b.f_q !== 0n))) {
    if (((b.f_q.f_v.f_kind.tag === {tag:2}.tag) && (b.f_q.f_v.f_target === e.f_target))) {
    b.f_q.f_v = e;
    (o_f_sync_munlock(b.f_mu));
    (rt.rt_try_send(b.f_ping, 1n));
    rt.rt_defer_drain_to(_dmark);
    return 1n;
    }
    }
    let elig = (() => { rt.rt_borrow_read(e); const __rc = o_f_gui_ev_eligible(b, e); rt.rt_unborrow(e); return __rc; })();
    if (((elig === 1n) && (b.f_elig >= b.f_cap))) {
    let rr = o_f_gui_en_rm_last_elig(b.f_q);
    b.f_q = rr.f_list;
    if ((rr.f_found !== null && rr.f_found !== 0n)) {
    b.f_elig = rt.rt_isub(b.f_elig, 1n);
    (rt.rt_sset(b.f_dropped, rt.rt_iadd(rt.rt_sget(b.f_dropped), 1n)));
    (rt.rt_sset(b.f_dp, rt.rt_iadd(rt.rt_sget(b.f_dp), 1n)));
    }
    }
    b.f_q = o_f_gui_en_cons(e, elig, b.f_q);
    b.f_elig = rt.rt_iadd(b.f_elig, elig);
    (o_f_sync_munlock(b.f_mu));
    (rt.rt_try_send(b.f_ping, 1n));
    rt.rt_defer_drain_to(_dmark);
    return 1n;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_EventBuf_pop(b) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    let rr = o_f_gui_en_rm_last(b.f_q);
    b.f_q = rr.f_list;
    if ((rr.f_found === null || rr.f_found === 0n)) {
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return null;
    }
    if ((rr.f_found.f_elig === 1n)) {
    b.f_elig = rt.rt_isub(b.f_elig, 1n);
    }
    let v = rr.f_found.f_v;
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return v;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_EventBuf_take_dp(b) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    let n = rt.rt_sget(b.f_dp);
    (rt.rt_sset(b.f_dp, 0n));
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return n;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_EventBuf_add_dropped(b, n) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    (rt.rt_sset(b.f_dropped, rt.rt_iadd(rt.rt_sget(b.f_dropped), n)));
    (rt.rt_sset(b.f_dp, rt.rt_iadd(rt.rt_sget(b.f_dp), n)));
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_EventBuf_add_dp(b, n) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    (rt.rt_sset(b.f_dp, rt.rt_iadd(rt.rt_sget(b.f_dp), n)));
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_EventBuf_closed_empty(b) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    let r = 0n;
    if (((rt.rt_sget(b.f_closed) === 1n) && (b.f_q === null || b.f_q === 0n))) {
    r = 1n;
    }
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return r;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_wt_del(l, h) {
    const _dmark = rt.rt_defer_mark();
    if ((l === null || l === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return null;
    }
    if ((l.f_h === h)) {
    rt.rt_defer_drain_to(_dmark);
    return l.f_next;
    }
    let rest = l.f_next;
    l.f_next = o_f_gui_wt_del(rest, h);
    rt.rt_defer_drain_to(_dmark);
    return l;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_eb_mark_dead(b, h) {
    const _dmark = rt.rt_defer_mark();
    b.f_q = o_f_gui_en_flip_close(b, b.f_q, h);
    b.f_wt = o_f_gui_wt_del(b.f_wt, h);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_cn_cons(v, next) {
    const _dmark = rt.rt_defer_mark();
    let c = {f_v:null,f_next:null};
    c.f_v = v;
    c.f_next = next;
    rt.rt_defer_drain_to(_dmark);
    return c;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_cn_rev(l) {
    const _dmark = rt.rt_defer_mark();
    let out = null;
    while ((l !== null && l !== 0n)) {
    let n = l.f_next;
    l.f_next = out;
    out = l;
    l = n;
    }
    rt.rt_defer_drain_to(_dmark);
    return out;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_CmdBuf_drain(b) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    let l = b.f_q;
    let n = b.f_len;
    b.f_q = null;
    b.f_len = 0n;
    (o_f_sync_munlock(b.f_mu));
    let i = 0n;
    while ((i < n)) {
    (rt.rt_try_send(b.f_room, 1n));
    i = rt.rt_iadd(i, 1n);
    }
    rt.rt_defer_drain_to(_dmark);
    return o_f_gui_cn_rev(l);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_CmdBuf_post(b, c) {
    const _dmark = rt.rt_defer_mark();
    while ((1n === 1n)) {
    (o_f_sync_mlock(b.f_mu));
    if ((rt.rt_sget(b.f_closed) === 1n)) {
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return 0n;
    }
    if ((b.f_len < b.f_cap)) {
    { const _ms1 = c.f_prop.f_val;
      if (_ms1.tag === 0) {
      let t = _ms1.p0.f_f0;
    c.f_prop.f_val = {tag:0,p0:{f_f0:o_f_gui_cb_intern_l(b, t)}};
      }
      else {
      }
    }
    if ((c.f_props !== null && c.f_props !== 0n)) {
    let i = 0n;
    while ((i < rt.rt_len(c.f_props.v))) {
    { const _ms2 = rt.rt_sidx(c.f_props.v, i).f_val;
      if (_ms2.tag === 0) {
      let t = _ms2.p0.f_f0;
    rt.rt_sidx(c.f_props.v, i).f_val = {tag:0,p0:{f_f0:o_f_gui_cb_intern_l(b, t)}};
      }
      else {
      }
    }
    i = rt.rt_iadd(i, 1n);
    }
    }
    b.f_q = o_f_gui_cn_cons(c, b.f_q);
    b.f_len = rt.rt_iadd(b.f_len, 1n);
    (rt.rt_sset(b.f_wakep, 1n));
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return 1n;
    }
    (o_f_sync_munlock(b.f_mu));
    (rt.rt_trap(21n));
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_last_dropped_cell() {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_last_dropped === null || o_g_gui_g_last_dropped === 0n)) {
    o_g_gui_g_last_dropped = rt.rt_mkshared(0n);
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_cell_take() {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_cell_mu !== null && o_g_gui_g_cell_mu !== 0n)) {
    (o_f_sync_mlock(o_g_gui_g_cell_mu));
    let n = o_g_gui_g_cells;
    if ((n !== null && n !== 0n)) {
    o_g_gui_g_cells = n.f_next;
    o_g_gui_g_cells_n = rt.rt_isub(o_g_gui_g_cells_n, 1n);
    }
    (o_f_sync_munlock(o_g_gui_g_cell_mu));
    if ((n !== null && n !== 0n)) {
    (rt.rt_sset(n.f_s, 0n));
    rt.rt_defer_drain_to(_dmark);
    return n.f_s;
    }
    }
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_mkshared(0n);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_cell_put(s) {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_cell_mu === null || o_g_gui_g_cell_mu === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    (o_f_sync_mlock(o_g_gui_g_cell_mu));
    if ((o_g_gui_g_cells_n >= 16n)) {
    (o_f_sync_munlock(o_g_gui_g_cell_mu));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    let n = {f_s:null,f_next:null};
    n.f_s = s;
    n.f_next = o_g_gui_g_cells;
    o_g_gui_g_cells = n;
    o_g_gui_g_cells_n = rt.rt_iadd(o_g_gui_g_cells_n, 1n);
    (o_f_sync_munlock(o_g_gui_g_cell_mu));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_reply_chan() {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_rp_mu !== null && o_g_gui_g_rp_mu !== 0n)) {
    (o_f_sync_mlock(o_g_gui_g_rp_mu));
    let n = o_g_gui_g_rp;
    if ((n !== null && n !== 0n)) {
    o_g_gui_g_rp = n.f_next;
    o_g_gui_g_rp_n = rt.rt_isub(o_g_gui_g_rp_n, 1n);
    }
    (o_f_sync_munlock(o_g_gui_g_rp_mu));
    if ((n !== null && n !== 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return n.f_c;
    }
    }
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_mkchan_scoped(o_g_gui_g_sess.f_mscope, 1n, o_drop_word);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_reply_pool_put(rc) {
    const _dmark = rt.rt_defer_mark();
    if ((globalThis.__oxl_ffi.rt_chan_is_closed(rc) !== 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((o_g_gui_g_rp_mu === null || o_g_gui_g_rp_mu === 0n)) {
    (rt.rt_close(rc));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    (o_f_sync_mlock(o_g_gui_g_rp_mu));
    if ((o_g_gui_g_rp_n >= 8n)) {
    (o_f_sync_munlock(o_g_gui_g_rp_mu));
    (rt.rt_close(rc));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    let n = {f_c:null,f_next:null};
    n.f_c = rc;
    n.f_next = o_g_gui_g_rp;
    o_g_gui_g_rp = n;
    o_g_gui_g_rp_n = rt.rt_iadd(o_g_gui_g_rp_n, 1n);
    (o_f_sync_munlock(o_g_gui_g_rp_mu));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_reply_done(rc, settled) {
    const _dmark = rt.rt_defer_mark();
    if ((rt.rt_sget(settled) !== 0n)) {
    (o_f_gui_cell_put(settled));
    (o_f_gui_reply_pool_put(rc));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    (o_f_gui_cell_put(settled));
    (rt.rt_close(rc));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_str_own(s) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return globalThis.__oxl_ffi.rt_str_own(s);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_cb_intern_l(b, s) {
    const _dmark = rt.rt_defer_mark();
    let n = {f_s:{u8:null,off:0,len:0},f_next:null};
    n.f_s = globalThis.__oxl_ffi.rt_str_own(s);
    n.f_next = b.f_strs;
    let r = n.f_s;
    b.f_strs = n;
    rt.rt_defer_drain_to(_dmark);
    return r;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_eb_intern_l(b, s) {
    const _dmark = rt.rt_defer_mark();
    let n = {f_s:{u8:null,off:0,len:0},f_next:null};
    n.f_s = globalThis.__oxl_ffi.rt_str_own(s);
    n.f_next = b.f_strs;
    let r = n.f_s;
    b.f_strs = n;
    rt.rt_defer_drain_to(_dmark);
    return r;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_sn_free_all(l) {
    const _dmark = rt.rt_defer_mark();
    while ((l !== null && l !== 0n)) {
    (globalThis.__oxl_ffi.rt_str_free(l.f_s));
    l = l.f_next;
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_CmdBuf_free_strs(b) {
    const _dmark = rt.rt_defer_mark();
    (o_f_gui_sn_free_all(b.f_strs));
    b.f_strs = null;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_EventBuf_free_strs(b) {
    const _dmark = rt.rt_defer_mark();
    (o_f_gui_sn_free_all(b.f_strs));
    b.f_strs = null;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_CmdBuf_take_wake(b) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(b.f_mu));
    let w = rt.rt_sget(b.f_wakep);
    (rt.rt_sset(b.f_wakep, 0n));
    (o_f_sync_munlock(b.f_mu));
    rt.rt_defer_drain_to(_dmark);
    return w;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_mk_cmd(kind, target, arg) {
    const _dmark = rt.rt_defer_mark();
    let c = {f_kind:{tag:0,p0:{}},f_target:0n,f_widget:{tag:0,p0:{}},f_prop:{f_id:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}},f_props:null,f_arg:0n,f_reply:null};
    c.f_kind = kind;
    c.f_target = target;
    c.f_widget = {tag:0};
    c.f_prop = {f_id:0n,f_val:{tag:2,p2:{f_f0:0n}}};
    c.f_props = null;
    c.f_arg = arg;
    c.f_reply = null;
    rt.rt_defer_drain_to(_dmark);
    return c;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_post_ff(c) {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_cb === null || o_g_gui_g_cb === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if (((() => { rt.rt_borrow_mut(o_g_gui_g_cb); const __rc = o_f_gui_CmdBuf_post(o_g_gui_g_cb, c); rt.rt_unborrow(o_g_gui_g_cb); return __rc; })() === 1n)) {
    (((_iv) => _iv.methods.wake(_iv.obj))(o_g_gui_g_sess.f_b));
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_post_reply(c) {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(o_g_gui_g_cb.f_mu));
    let cl = rt.rt_sget(o_g_gui_g_cb.f_closed);
    (o_f_sync_munlock(o_g_gui_g_cb.f_mu));
    if ((cl === 1n)) {
    rt.rt_defer_drain_to(_dmark);
    return o_f_gui_err_stopped();
    }
    if (((() => { rt.rt_borrow_mut(o_g_gui_g_cb); const __rc = o_f_gui_CmdBuf_post(o_g_gui_g_cb, c); rt.rt_unborrow(o_g_gui_g_cb); return __rc; })() === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return o_f_gui_err_stopped();
    }
    (((_iv) => _iv.methods.wake(_iv.obj))(o_g_gui_g_sess.f_b));
    rt.rt_defer_drain_to(_dmark);
    return null;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_credit_unless(sent, n) {
    const _dmark = rt.rt_defer_mark();
    if ((rt.rt_sget(sent) === 0n)) {
    ((() => { rt.rt_borrow_mut(o_g_gui_g_eb); o_f_gui_EventBuf_add_dropped(o_g_gui_g_eb, n); rt.rt_unborrow(o_g_gui_g_eb); })());
    }
    (o_f_gui_cell_put(sent));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_credit_marker(sent, n) {
    const _dmark = rt.rt_defer_mark();
    if ((rt.rt_sget(sent) === 0n)) {
    ((() => { rt.rt_borrow_mut(o_g_gui_g_eb); o_f_gui_EventBuf_add_dp(o_g_gui_g_eb, n); rt.rt_unborrow(o_g_gui_g_eb); })());
    }
    (o_f_gui_cell_put(sent));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_eb_count_rest() {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(o_g_gui_g_eb.f_mu));
    let n = (() => { rt.rt_borrow_read(o_g_gui_g_eb.f_q); const __rc = o_f_gui_en_len(o_g_gui_g_eb.f_q); rt.rt_unborrow(o_g_gui_g_eb.f_q); return __rc; })();
    o_g_gui_g_eb.f_q = null;
    (rt.rt_sset(o_g_gui_g_eb.f_dropped, rt.rt_iadd(rt.rt_sget(o_g_gui_g_eb.f_dropped), n)));
    (rt.rt_sset(o_g_gui_g_eb.f_dp, rt.rt_iadd(rt.rt_sget(o_g_gui_g_eb.f_dp), n)));
    (o_f_sync_munlock(o_g_gui_g_eb.f_mu));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_cb_shutdown() {
    const _dmark = rt.rt_defer_mark();
    (o_f_sync_mlock(o_g_gui_g_cb.f_mu));
    (rt.rt_sset(o_g_gui_g_cb.f_closed, 1n));
    let l = o_g_gui_g_cb.f_q;
    o_g_gui_g_cb.f_q = null;
    o_g_gui_g_cb.f_len = 0n;
    (o_f_sync_munlock(o_g_gui_g_cb.f_mu));
    (rt.rt_close(o_g_gui_g_cb.f_room));
    l = o_f_gui_cn_rev(l);
    while ((l !== null && l !== 0n)) {
    let c = l.f_v;
    let r = l.f_next;
    l.f_next = null;
    if (((c.f_kind.tag === {tag:5}.tag) || (c.f_kind.tag === {tag:0}.tag))) {
    let rc = {f_e:0n,f_handle:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}};
    rc.f_e = o_f_gui_err_stopped();
    rc.f_handle = 0n;
    rc.f_val = {tag:2,p2:{f_f0:0n}};
    (rt.rt_try_send(c.f_reply, rc));
    }
    l = r;
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_stop() {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_sess !== null && o_g_gui_g_sess !== 0n)) {
    (((_iv) => _iv.methods.stop(_iv.obj))(o_g_gui_g_sess.f_b));
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_events_dropped() {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_eb !== null && o_g_gui_g_eb !== 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_sget(o_g_gui_g_eb.f_dropped);
    }
    if ((o_g_gui_g_last_dropped !== null && o_g_gui_g_last_dropped !== 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_sget(o_g_gui_g_last_dropped);
    }
    rt.rt_defer_drain_to(_dmark);
    return 0n;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_kind_i(k) {
    const _dmark = rt.rt_defer_mark();
    { const _ms5 = k;
      if (_ms5.tag === 0) {
    rt.rt_defer_drain_to(_dmark);
    return 0n;
      }
      else if (_ms5.tag === 1) {
    rt.rt_defer_drain_to(_dmark);
    return 1n;
      }
      else if (_ms5.tag === 2) {
    rt.rt_defer_drain_to(_dmark);
    return 2n;
      }
      else if (_ms5.tag === 3) {
    rt.rt_defer_drain_to(_dmark);
    return 3n;
      }
      else if (_ms5.tag === 4) {
    rt.rt_defer_drain_to(_dmark);
    return 4n;
      }
      else if (_ms5.tag === 5) {
    rt.rt_defer_drain_to(_dmark);
    return 5n;
      }
      else if (_ms5.tag === 6) {
    rt.rt_defer_drain_to(_dmark);
    return 6n;
      }
      else if (_ms5.tag === 7) {
    rt.rt_defer_drain_to(_dmark);
    return 7n;
      }
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Window_handle(w) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return w.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Window_kind(w) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:0};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_VBox_handle(w) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return w.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_VBox_kind(w) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:1};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_HBox_handle(w) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return w.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_HBox_kind(w) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:2};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Label_handle(l) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return l.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Label_kind(l) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:3};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Button_handle(b) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return b.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Button_kind(b) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:4};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Entry_handle(e) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return e.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Entry_kind(e) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:5};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_List_handle(l) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return l.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_List_kind(l) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:6};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Scrolled_handle(s) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return s.f_h;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Scrolled_kind(s) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {tag:7};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_props1(id, v) {
    const _dmark = rt.rt_defer_mark();
    let p = (() => { const _n = Number(1n); const _a = new Array(_n); for (let _i = 0; _i < _n; _i++) _a[_i] = {f_id:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}}; return {a: _a, off: 0, len: _n, cap: _n}; })();
    rt.rt_sidx_set(p, 0n, {f_id:id,f_val:v});
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_slice_own(p);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_append(parent, child) {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_eb === null || o_g_gui_g_eb === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    (o_f_sync_mlock(o_g_gui_g_eb.f_mu));
    o_g_gui_g_eb.f_wt = o_f_gui_wt_set(o_g_gui_g_eb.f_wt, ((_iv) => _iv.methods.handle(_iv.obj))(child), 3n, ((_iv) => _iv.methods.handle(_iv.obj))(parent));
    (o_f_sync_munlock(o_g_gui_g_eb.f_mu));
    (o_f_gui_post_ff(o_f_gui_mk_cmd({tag:2}, ((_iv) => _iv.methods.handle(_iv.obj))(parent), ((_iv) => _iv.methods.handle(_iv.obj))(child))));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_remove(w) {
    const _dmark = rt.rt_defer_mark();
    if ((o_g_gui_g_eb === null || o_g_gui_g_eb === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    let h = ((_iv) => _iv.methods.handle(_iv.obj))(w);
    (o_f_sync_mlock(o_g_gui_g_eb.f_mu));
    let wt = (() => { rt.rt_borrow_read(o_g_gui_g_eb.f_wt); const __rc = o_f_gui_wt_get(o_g_gui_g_eb.f_wt, h); rt.rt_unborrow(o_g_gui_g_eb.f_wt); return __rc; })();
    (o_f_sync_munlock(o_g_gui_g_eb.f_mu));
    if ((wt.f_parent !== 0n)) {
    (o_f_gui_post_ff(o_f_gui_mk_cmd({tag:3}, wt.f_parent, h)));
    }
    (o_f_gui_post_ff(o_f_gui_mk_cmd({tag:4}, h, 0n)));
    (o_f_sync_mlock(o_g_gui_g_eb.f_mu));
    ((() => { rt.rt_borrow_mut(o_g_gui_g_eb); o_f_gui_eb_mark_dead(o_g_gui_g_eb, h); rt.rt_unborrow(o_g_gui_g_eb); })());
    (o_f_sync_munlock(o_g_gui_g_eb.f_mu));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_set_prop(h, id, v) {
    const _dmark = rt.rt_defer_mark();
    let c = o_f_gui_mk_cmd({tag:1}, h, 0n);
    c.f_prop = {f_id:id,f_val:v};
    (o_f_gui_post_ff(c));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_gui_Entry_set_text(e, s) {
    const _dmark = rt.rt_defer_mark();
    (o_f_gui_set_prop(e.f_h, o_g_gui_P_TEXT, {tag:0,p0:{f_f0:s}}));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_al_add(h) {
    const _dmark = rt.rt_defer_mark();
    let a = {f_h:0n,f_next:null};
    a.f_h = h;
    a.f_next = o_g_dom_g_alive;
    o_g_dom_g_alive = a;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_al_has(h) {
    const _dmark = rt.rt_defer_mark();
    let l = o_g_dom_g_alive;
    while ((l !== null && l !== 0n)) {
    if ((l.f_h === h)) {
    rt.rt_defer_drain_to(_dmark);
    return 1n;
    }
    l = l.f_next;
    }
    rt.rt_defer_drain_to(_dmark);
    return 0n;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_al_del(h) {
    const _dmark = rt.rt_defer_mark();
    let out = null;
    let l = o_g_dom_g_alive;
    while ((l !== null && l !== 0n)) {
    let n = l.f_next;
    if ((l.f_h !== h)) {
    l.f_next = out;
    out = l;
    } else {
    l.f_next = null;
    }
    l = n;
    }
    o_g_dom_g_alive = out;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_backend() {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return {f_stopf:rt.rt_mkshared(0n),f_wakech:rt.rt_mkchan_scoped(null, 0, null)};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_headless() {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return o_f_dom_backend();
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_fire(d, h, kind) {
    const _dmark = rt.rt_defer_mark();
    (globalThis.__oxl_ffi.oxl_dom_fire(h, kind));
    (rt.rt_try_send(d.f_wakech, 1n));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_tag(d, h) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str(globalThis.__oxl_ffi.oxl_dom_tag(h));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_tag_of(kind) {
    const _dmark = rt.rt_defer_mark();
    { const _ms6 = kind;
      if (_ms6.tag === 0) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("ZGl2");
      }
      else if (_ms6.tag === 1) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("ZGl2");
      }
      else if (_ms6.tag === 2) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("ZGl2");
      }
      else if (_ms6.tag === 3) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("c3Bhbg==");
      }
      else if (_ms6.tag === 4) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("YnV0dG9u");
      }
      else if (_ms6.tag === 5) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("aW5wdXQ=");
      }
      else if (_ms6.tag === 6) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("dWw=");
      }
      else if (_ms6.tag === 7) {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("ZGl2");
      }
      else {
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("ZGl2");
      }
    }
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_str_lit("ZGl2");
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_new(d, kind, props) {
    const _dmark = rt.rt_defer_mark();
    let h = globalThis.__oxl_ffi.oxl_dom_create(o_f_dom_tag_of(kind));
    if ((h === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return {val: 0n, err: o_f_errors_new(rt.rt_str_lit("Z3VpL2RvbTogZWxlbWVudCBjcmVhdGUgZmFpbGVk"))};
    }
    if ((props !== null && props !== 0n)) {
    let i = 0n;
    while ((i < rt.rt_len(props.v))) {
    (o_f_dom_Dom_set_prop(d, h, rt.rt_sidx(props.v, i)));
    i = rt.rt_iadd(i, 1n);
    }
    }
    (o_f_dom_al_add(h));
    { const _ms7 = kind;
      if (_ms7.tag === 0) {
    (globalThis.__oxl_ffi.oxl_dom_attach(globalThis.__oxl_ffi.oxl_dom_root(), h));
    (globalThis.__oxl_ffi.oxl_dom_listen(h, o_g_dom_D_CLOSE));
      }
      else if (_ms7.tag === 4) {
    (globalThis.__oxl_ffi.oxl_dom_listen(h, o_g_dom_D_CLICK));
      }
      else if (_ms7.tag === 5) {
    (globalThis.__oxl_ffi.oxl_dom_listen(h, o_g_dom_D_INPUT));
    (globalThis.__oxl_ffi.oxl_dom_listen(h, o_g_dom_D_ENTER));
      }
      else {
      }
    }
    rt.rt_defer_drain_to(_dmark);
    return {val: h, err: null};
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_set_prop(d, h, p) {
    const _dmark = rt.rt_defer_mark();
    { const _ms8 = p.f_val;
      if (_ms8.tag === 0) {
      let s = _ms8.p0.f_f0;
    (globalThis.__oxl_ffi.oxl_dom_set_text(h, p.f_id, s));
      }
      else {
    (rt.rt_println_str(rt.rt_str_lit("Z3VpL2RvbTogbm9uLXRleHQgcHJvcCB3cml0ZSB1bnN1cHBvcnRlZA==")));
      }
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_attach(d, parent, child) {
    const _dmark = rt.rt_defer_mark();
    (globalThis.__oxl_ffi.oxl_dom_attach(parent, child));
    if ((rt.rt_streq(o_f_dom_Dom_tag(d, parent), rt.rt_str_lit("dWw=")))) {
    (globalThis.__oxl_ffi.oxl_dom_listen(child, o_g_dom_D_ROWCLICK));
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_detach(d, parent, child) {
    const _dmark = rt.rt_defer_mark();
    (globalThis.__oxl_ffi.oxl_dom_detach(parent, child));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_destroy(d, h) {
    const _dmark = rt.rt_defer_mark();
    if ((o_f_dom_al_has(h) === 1n)) {
    (o_f_dom_al_del(h));
    }
    (globalThis.__oxl_ffi.oxl_dom_destroy(h));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_exec(d, c) {
    const _dmark = rt.rt_defer_mark();
    if ((c.f_kind.tag === {tag:0}.tag)) {
    if (((c.f_target !== 0n) && (o_f_dom_al_has(c.f_target) === 0n))) {
    let r = {f_e:0n,f_handle:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}};
    r.f_e = o_f_gui_err_gone();
    r.f_handle = 0n;
    r.f_val = {tag:2,p2:{f_f0:0n}};
    (rt.rt_try_send(c.f_reply, r));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    const _r9 = o_f_dom_Dom_new(d, c.f_widget, c.f_props);
    let h = _r9.val;
    let e = _r9.err;
    if ((e !== null && e !== 0n)) {
    let r = {f_e:0n,f_handle:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}};
    r.f_e = e;
    r.f_handle = 0n;
    r.f_val = {tag:2,p2:{f_f0:0n}};
    (rt.rt_try_send(c.f_reply, r));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_target !== 0n)) {
    (o_f_dom_Dom_attach(d, c.f_target, h));
    }
    let r2 = {f_e:0n,f_handle:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}};
    r2.f_e = null;
    r2.f_handle = h;
    r2.f_val = {tag:2,p2:{f_f0:0n}};
    if ((!rt.rt_try_send(c.f_reply, r2))) {
    (o_f_dom_Dom_destroy(d, h));
    }
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_kind.tag === {tag:1}.tag)) {
    (o_f_dom_Dom_set_prop(d, c.f_target, c.f_prop));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_kind.tag === {tag:2}.tag)) {
    (o_f_dom_Dom_attach(d, c.f_target, c.f_arg));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_kind.tag === {tag:3}.tag)) {
    (o_f_dom_Dom_detach(d, c.f_target, c.f_arg));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_kind.tag === {tag:4}.tag)) {
    (o_f_dom_Dom_destroy(d, c.f_target));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_kind.tag === {tag:6}.tag)) {
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_kind.tag === {tag:5}.tag)) {
    if ((o_f_dom_al_has(c.f_target) === 0n)) {
    let r = {f_e:0n,f_handle:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}};
    r.f_e = o_f_gui_err_gone();
    r.f_handle = 0n;
    r.f_val = {tag:2,p2:{f_f0:0n}};
    (rt.rt_try_send(c.f_reply, r));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    if ((c.f_prop.f_id === o_g_gui_P_ROWS)) {
    let n = globalThis.__oxl_ffi.oxl_dom_read_num(c.f_target, c.f_prop.f_id);
    let r = {f_e:0n,f_handle:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}};
    r.f_handle = 0n;
    if ((n < 0n)) {
    r.f_e = o_f_errors_new(rt.rt_str_lit("Z3VpL2RvbTogUF9ST1dTIG9uIG5vbi1saXN0"));
    r.f_val = {tag:2,p2:{f_f0:0n}};
    } else {
    r.f_e = null;
    r.f_val = {tag:2,p2:{f_f0:n}};
    }
    (rt.rt_try_send(c.f_reply, r));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    let r2 = {f_e:0n,f_handle:0n,f_val:{tag:0,p0:{f_f0:{u8:null,off:0,len:0}}}};
    r2.f_handle = 0n;
    if ((globalThis.__oxl_ffi.oxl_dom_read_has(c.f_target, c.f_prop.f_id) === 0n)) {
    r2.f_e = o_f_errors_new(rt.rt_str_lit("Z3VpL2RvbTogdW5zdXBwb3J0ZWQgcHJvcA=="));
    r2.f_val = {tag:2,p2:{f_f0:0n}};
    (rt.rt_try_send(c.f_reply, r2));
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    let s = o_f_gui_str_own(rt.rt_str(globalThis.__oxl_ffi.oxl_dom_read_str(c.f_target, c.f_prop.f_id)));
    r2.f_e = null;
    r2.f_val = {tag:0,p0:{f_f0:s}};
    if ((!rt.rt_try_send(c.f_reply, r2))) {
    (globalThis.__oxl_ffi.rt_str_free(s));
    }
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_deliver(d, events, h, k, aux) {
    const _dmark = rt.rt_defer_mark();
    let e = {f_kind:{tag:0,p0:{}},f_target:0n,f_data:{tag:0,p0:{}}};
    e.f_target = h;
    e.f_data = {tag:0};
    if ((k === o_g_dom_D_CLICK)) {
    e.f_kind = {tag:0};
    }
    if ((k === o_g_dom_D_ENTER)) {
    e.f_kind = {tag:1};
    }
    if ((k === o_g_dom_D_CLOSE)) {
    e.f_kind = {tag:3};
    }
    if ((k === o_g_dom_D_ROWCLICK)) {
    e.f_kind = {tag:4};
    e.f_data = {tag:2,p2:{f_f0:aux}};
    }
    if ((k === o_g_dom_D_INPUT)) {
    e.f_kind = {tag:2};
    if ((globalThis.__oxl_ffi.oxl_dom_read_has(h, o_g_gui_P_TEXT) === 1n)) {
    e.f_data = {tag:1,p1:{f_f0:rt.rt_str(globalThis.__oxl_ffi.oxl_dom_read_str(h, o_g_gui_P_TEXT))}};
    }
    }
    (o_f_gui_EventBuf_post(events, e));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_pump(d, events, cmds) {
    const _dmark = rt.rt_defer_mark();
    ((((1n === 0n)) ? void 0 : rt.rt_trap(3n)));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_susp_pump(d) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return 1n;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_pump_iter(d, events, cmds) {
    const _dmark = rt.rt_defer_mark();
    while ((1n === 1n)) {
    let h = globalThis.__oxl_ffi.oxl_dom_ev_next();
    if ((h === 0n)) {
    break;
    }
    let k = globalThis.__oxl_ffi.oxl_dom_ev_kind();
    let a = globalThis.__oxl_ffi.oxl_dom_ev_aux();
    (globalThis.__oxl_ffi.oxl_dom_ev_pop());
    (o_f_dom_Dom_deliver(d, events, h, k, a));
    }
    let q = o_f_gui_CmdBuf_drain(cmds);
    let worked = 0n;
    while ((q !== null && q !== 0n)) {
    let c = q.f_v;
    let r = q.f_next;
    q.f_next = null;
    (o_f_dom_Dom_exec(d, c));
    q = r;
    worked = 1n;
    }
    rt.rt_defer_drain_to(_dmark);
    return worked;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_pump_edge(d) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return d.f_wakech;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_stopped(d) {
    const _dmark = rt.rt_defer_mark();
    rt.rt_defer_drain_to(_dmark);
    return rt.rt_sget(d.f_stopf);
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_pump_fin(d) {
    const _dmark = rt.rt_defer_mark();
    while ((1n === 1n)) {
    let l = o_g_dom_g_alive;
    if ((l === null || l === 0n)) {
    rt.rt_defer_drain_to(_dmark);
    return;
    }
    let h = l.f_h;
    (o_f_dom_al_del(h));
    (globalThis.__oxl_ffi.oxl_dom_destroy(h));
    }
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_stop(d) {
    const _dmark = rt.rt_defer_mark();
    (rt.rt_sset(d.f_stopf, 1n));
    (rt.rt_try_send(d.f_wakech, 1n));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_dom_Dom_wake(d) {
    const _dmark = rt.rt_defer_mark();
    (rt.rt_try_send(d.f_wakech, 1n));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_row_put(del, box) {
    const _dmark = rt.rt_defer_mark();
    let r = {f_del:0n,f_box:0n,f_next:null};
    r.f_del = del;
    r.f_box = box;
    (o_f_sync_mlock(o_g_g_rows_mu));
    r.f_next = o_g_g_rows;
    o_g_g_rows = r;
    (o_f_sync_munlock(o_g_g_rows_mu));
    rt.rt_defer_drain_to(_dmark);
}

function o_f_row_take(del) {
    const _dmark = rt.rt_defer_mark();
    let out = null;
    let found = 0n;
    (o_f_sync_mlock(o_g_g_rows_mu));
    let l = o_g_g_rows;
    o_g_g_rows = null;
    while ((l !== null && l !== 0n)) {
    let n = l.f_next;
    if ((l.f_del === del)) {
    found = l.f_box;
    l.f_next = null;
    } else {
    l.f_next = out;
    out = l;
    }
    l = n;
    }
    o_g_g_rows = out;
    (o_f_sync_munlock(o_g_g_rows_mu));
    rt.rt_defer_drain_to(_dmark);
    return found;
    rt.rt_defer_drain_to(_dmark);
}

function o_f_app(events) {
    const _dmark = rt.rt_defer_mark();
    { const _t10 = o_frm_ui();
      _t10.p_events = events;
      rt.rt_spawn_task(_t10); }
    rt.rt_defer_drain_to(_dmark);
}

async function oxl_main() {
    o_g_gui_P_TEXT = 1n;    o_g_gui_P_TITLE = 2n;    o_g_gui_P_PLACEHOLDER = 3n;    o_g_gui_P_ROWS = 4n;    o_g_gui_g_event_cap = 256n;    o_g_gui_g_cmd_cap = 512n;    o_g_gui_g_drain_ms = 250n;    o_g_gui_g_running = 0n;    o_g_gui_g_eb = null;    o_g_gui_g_cb = null;    o_g_gui_g_sess = null;    o_g_gui_g_last_dropped = null;    o_g_gui_g_rp = null;    o_g_gui_g_rp_n = 0n;    o_g_gui_g_rp_mu = null;    o_g_gui_g_cells = null;    o_g_gui_g_cells_n = 0n;    o_g_gui_g_cell_mu = null;    o_g_dom_D_CLICK = 1n;    o_g_dom_D_INPUT = 2n;    o_g_dom_D_ENTER = 3n;    o_g_dom_D_ROWCLICK = 4n;    o_g_dom_D_CLOSE = 5n;    o_g_dom_g_alive = null;    o_g_g_rows = null;    o_g_g_rows_mu = o_f_sync_mutex();    o_g_g_lb = {f_h:0n};    o_g_g_en = {f_h:0n};    o_g_g_add = {f_h:0n};    o_g_g_d = o_f_dom_headless();    o_g_g_selftest = 0n;    o_g_g_hb = o_f_sync_counter();    o_g_g_rm = o_f_sync_counter();    await rt.rt_run_root(o_frm_main());
}
function o_drop_word(_v) {}
rt.__oxl_boot(oxl_main)
