/* gtk_shim.c — C ABI shim between extra/gui/gtk and GTK4.
 *
 * Generalizes the gui-todo pilot (spec G2): GTK's signal API is
 * macro-based, so every entry point here is a plain C symbol on
 * scalar values, callable via `extern fn` in gtk.oxl and linked by
 * the app's build script (`pkg-config --cflags/--libs gtk4`).
 *
 * Handles are monotonically allocated int64s starting at 1 — never
 * reissued for the life of the process (the backend protocol pins
 * this: a stale queued event must never bind to a recycled widget).
 * The table maps handle -> {widget, kind}; widget pointers are never
 * exposed.
 *
 * Toolkit signals never cross into OXL directly: trampolines push
 * raw {handle, event, aux} triples onto a C ring, and pump drains the
 * ring each main-context iteration, marshalling gui.Events there.
 * All GTK access happens on the task that runs gx_iter (the app
 * root task / GUI thread); gx_emit defers to that thread via
 * g_main_context_invoke so tests can drive real signals from app
 * tasks.
 */
#include <gtk/gtk.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../../runtime/rt.h" /* OxlStr layout */
#include <signal.h>
#include <unistd.h>

/* widget kinds — mirror gui.WidgetKind / mock kind_to_i */
#define K_WINDOW    1
#define K_VBOX      2
#define K_HBOX      3
#define K_LABEL     4
#define K_BUTTON    5
#define K_ENTRY     6
#define K_LIST      7
#define K_SCROLLED  8

/* ring event kinds — decoded by gtk.oxl's pump */
#define E_CLICKED         1
#define E_ACTIVATED       2
#define E_TEXT_CHANGED    3
#define E_CLOSE_REQUESTED 4
#define E_ROW_ACTIVATED   5

/* protocol prop ids — mirror gui.oxl */
#define P_TEXT        1
#define P_TITLE       2
#define P_PLACEHOLDER 3
#define P_ROWS        4 /* read-only: list row count */

/* ---- handle table ---- */
typedef struct HE {
    int64_t h;
    GtkWidget *w;
    int kind;
    int dead;
    struct HE *next;
} HE;
static HE *handles;
static int64_t hnext;

/* widget finalized by any path marks its handle dead — cascade
 * kills (window teardown frees children, a removed list row frees
 * its child) can never leave the table pointing at freed memory */
static void he_notify(gpointer data, GObject *old) {
    (void)old;
    HE *e = data;
    e->dead = 1;
    e->w = NULL;
}

static HE *he_find(int64_t h) {
    for (HE *e = handles; e; e = e->next)
        if (e->h == h)
            return e;
    return NULL;
}

static int64_t he_add(GtkWidget *w, int kind) {
    HE *e = malloc(sizeof *e);
    e->h = ++hnext;
    e->w = w;
    e->kind = kind;
    e->dead = 0;
    e->next = handles;
    handles = e;
    g_object_weak_ref(G_OBJECT(w), he_notify, e);
    return e->h;
}

/* ---- event ring ---- */
#define EV_CAP 1024 /* power of two */
typedef struct { int64_t h, aux; int kind; } Ev;
static Ev ring[EV_CAP];
static int rhead, rtail;
static Ev cur;

/* Trampolines and consumers are both on the GUI thread — no locking.
 * A full ring drops the oldest entry; the core EventBuf's own
 * overflow accounting is the app's loss signal, so a silently
 * overwritten ring slot is acceptable and bounded. */
static long g_n_invoke, g_n_emitcb, g_n_evpush, g_n_hedead;
static void dump_stats(void) {
    char b[160];
    int n = snprintf(b, sizeof b, "[shim] invoke=%ld emitcb=%ld evpush=%ld hedead=%ld\n",
                     g_n_invoke, g_n_emitcb, g_n_evpush, g_n_hedead);
    (void)!write(2, b, (size_t)n);
}
static void stats_sig(int sig) { (void)sig; dump_stats(); _exit(1); }
__attribute__((constructor)) static void reg_stats(void) {
    atexit(dump_stats);
    signal(SIGTERM, stats_sig);
    signal(SIGINT, stats_sig);
}

static void ev_push(int64_t h, int kind, int64_t aux) {
    g_n_evpush++;
    int n = (rhead + 1) & (EV_CAP - 1);
    if (n == rtail)
        rtail = (rtail + 1) & (EV_CAP - 1);
    ring[rhead].h = h;
    ring[rhead].kind = kind;
    ring[rhead].aux = aux;
    rhead = n;
}

int64_t gx_ev_next(void) {
    if (rtail == rhead)
        return 0;
    cur = ring[rtail];
    rtail = (rtail + 1) & (EV_CAP - 1);
    return cur.h;
}
int64_t gx_ev_kind(void) { return cur.kind; }
int64_t gx_ev_aux(void) { return cur.aux; }

/* ---- signal trampolines ---- */
static void t_clicked(GtkWidget *w, gpointer data) {
    (void)data;
    for (HE *e = handles; e; e = e->next)
        if (e->w == w) { ev_push(e->h, E_CLICKED, 0); return; }
}
static void t_activate(GtkWidget *w, gpointer data) {
    (void)data;
    for (HE *e = handles; e; e = e->next)
        if (e->w == w) { ev_push(e->h, E_ACTIVATED, 0); return; }
}
static void t_changed(GtkWidget *w, gpointer data) {
    (void)data;
    for (HE *e = handles; e; e = e->next)
        if (e->w == w) { ev_push(e->h, E_TEXT_CHANGED, 0); return; }
}
static void t_row_activated(GtkListBox *lb, GtkListBoxRow *row, gpointer data) {
    (void)data;
    int64_t idx = row ? gtk_list_box_row_get_index(row) : -1;
    for (HE *e = handles; e; e = e->next)
        if (e->w == GTK_WIDGET(lb)) { ev_push(e->h, E_ROW_ACTIVATED, idx); return; }
}
/* close-request is veto-backed: the event posts and the window
 * survives — the app answers with gui.remove (destroy) or keeps it */
static gboolean t_close_req(GtkWindow *w, gpointer data) {
    (void)data;
    for (HE *e = handles; e; e = e->next)
        if (e->w == GTK_WIDGET(w)) { ev_push(e->h, E_CLOSE_REQUESTED, 0); break; }
    return TRUE;
}

/* ---- lifecycle ---- */
void gx_init(void) { gtk_init(); }

int64_t gx_create(int64_t kind) {
    GtkWidget *w = NULL;
    switch (kind) {
    case K_WINDOW: {
        w = gtk_window_new();
        g_signal_connect(w, "close-request", G_CALLBACK(t_close_req), NULL);
        break;
    }
    case K_VBOX:
        w = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        break;
    case K_HBOX:
        w = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
        break;
    case K_LABEL:
        w = gtk_label_new("");
        break;
    case K_BUTTON:
        w = gtk_button_new_with_label("");
        g_signal_connect(w, "clicked", G_CALLBACK(t_clicked), NULL);
        break;
    case K_ENTRY:
        w = gtk_entry_new();
        g_signal_connect(w, "changed", G_CALLBACK(t_changed), NULL);
        g_signal_connect(w, "activate", G_CALLBACK(t_activate), NULL);
        break;
    case K_LIST:
        w = gtk_list_box_new();
        g_signal_connect(w, "row-activated", G_CALLBACK(t_row_activated), NULL);
        break;
    case K_SCROLLED:
        w = gtk_scrolled_window_new();
        gtk_widget_set_vexpand(w, TRUE);
        break;
    default:
        fprintf(stderr, "gx_create: unknown kind %lld\n", (long long)kind);
        return 0;
    }
    return he_add(w, (int)kind);
}

/* destroy — the single release op; idempotent on a dead handle. */
void gx_destroy(int64_t h) {
    HE *e = he_find(h);
    if (!e || e->dead)
        return;
    e->dead = 1;
    GtkWidget *w = e->w;
    e->w = NULL;
    g_object_weak_unref(G_OBJECT(w), he_notify, e);
    if (e->kind == K_WINDOW) {
        gtk_window_destroy(GTK_WINDOW(w));
        return;
    }
    /* a widget inside a GtkListBox is wrapped in a ListBoxRow — the
     * row is the list's real child, so removing the row takes the
     * subtree with it */
    GtkWidget *row = GTK_IS_LIST_BOX_ROW(w)
        ? w : gtk_widget_get_ancestor(w, GTK_TYPE_LIST_BOX_ROW);
    if (row) {
        GtkWidget *lb = gtk_widget_get_parent(row);
        if (lb && GTK_IS_LIST_BOX(lb)) {
            gtk_list_box_remove(GTK_LIST_BOX(lb), row);
            return;
        }
    }
    /* GTK4 has no floating refs: unparent on a solely-parent-owned
     * widget finalizes it on the spot. ref first so ours keeps it
     * alive, then drop that ref — net effect is exactly one release */
    if (gtk_widget_get_parent(w)) {
        g_object_ref(w);
        gtk_widget_unparent(w);
        g_object_unref(w);
        return;
    }
    /* unattached (never parented, or detached with a held ref): the
     * outstanding ref is ours — drop it */
    g_object_unref(w);
}

/* ---- props ---- */
static char *dup_oxlstr(OxlStr s) { return g_strndup(s.p, (gsize)s.n); }

/* set a text-valued prop: P_TEXT, P_TITLE, P_PLACEHOLDER */
void gx_set_text(int64_t h, int64_t id, OxlStr s) {
    HE *e = he_find(h);
    if (!e || e->dead) {
        fprintf(stderr, "gx_set_text: dead handle %lld\n", (long long)h);
        return;
    }
    char *z = dup_oxlstr(s);
    switch (e->kind) {
    case K_WINDOW:
        if (id == P_TITLE)
            gtk_window_set_title(GTK_WINDOW(e->w), z);
        break;
    case K_LABEL:
        if (id == P_TEXT)
            gtk_label_set_text(GTK_LABEL(e->w), z);
        break;
    case K_BUTTON:
        if (id == P_TEXT)
            gtk_button_set_label(GTK_BUTTON(e->w), z);
        break;
    case K_ENTRY:
        if (id == P_TEXT)
            gtk_editable_set_text(GTK_EDITABLE(e->w), z);
        else if (id == P_PLACEHOLDER)
            g_object_set(e->w, "placeholder-text", z, NULL);
        break;
    default:
        break;
    }
    g_free(z);
}

/* text-valued reads: entry text/placeholder, label text, button
 * label, window title. Borrowed pointer — copy before next gtk call. */
const char *gx_read_str(int64_t h, int64_t id) {
    HE *e = he_find(h);
    if (!e || e->dead)
        return NULL;
    switch (e->kind) {
    case K_WINDOW:
        if (id == P_TITLE)
            return gtk_window_get_title(GTK_WINDOW(e->w));
        return NULL;
    case K_LABEL:
        if (id == P_TEXT)
            return gtk_label_get_text(GTK_LABEL(e->w));
        return NULL;
    case K_BUTTON:
        if (id == P_TEXT)
            return gtk_button_get_label(GTK_BUTTON(e->w));
        return NULL;
    case K_ENTRY:
        if (id == P_TEXT)
            return gtk_editable_get_text(GTK_EDITABLE(e->w));
        if (id == P_PLACEHOLDER) {
            const char *p = NULL;
            g_object_get(e->w, "placeholder-text", &p, NULL);
            return p;
        }
        return NULL;
    default:
        return NULL;
    }
}

/* does (kind, prop id) name a readable property? Pure switch — a
 * 0 here means the read is unsupported, not that the value is absent */
int64_t gx_read_has(int64_t h, int64_t id) {
    HE *e = he_find(h);
    if (!e || e->dead)
        return 0;
    switch (e->kind) {
    case K_WINDOW:
        return id == P_TITLE;
    case K_LABEL:
    case K_BUTTON:
        return id == P_TEXT;
    case K_ENTRY:
        return id == P_TEXT || id == P_PLACEHOLDER;
    case K_LIST:
        return id == P_ROWS;
    default:
        return 0;
    }
}

/* int-valued reads: P_ROWS on a list. -1 = unsupported. */
int64_t gx_read_num(int64_t h, int64_t id) {
    HE *e = he_find(h);
    if (!e || e->dead)
        return -1;
    if (e->kind == K_LIST && id == P_ROWS) {
        int64_t n = 0;
        for (GtkWidget *c = gtk_widget_get_first_child(e->w);
             c; c = gtk_widget_get_next_sibling(c))
            n++;
        return n;
    }
    return -1;
}

/* ---- tree edges ---- */
void gx_attach(int64_t parent, int64_t child) {
    HE *p = he_find(parent), *c = he_find(child);
    if (!p || p->dead || !c || c->dead) {
        fprintf(stderr, "gx_attach: dead handle %lld->%lld\n",
                (long long)parent, (long long)child);
        return;
    }
    switch (p->kind) {
    case K_WINDOW:
        gtk_window_set_child(GTK_WINDOW(p->w), c->w);
        gtk_window_present(GTK_WINDOW(p->w));
        break;
    case K_VBOX:
    case K_HBOX:
        gtk_box_append(GTK_BOX(p->w), c->w);
        break;
    case K_SCROLLED:
        gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(p->w), c->w);
        break;
    case K_LIST:
        gtk_list_box_append(GTK_LIST_BOX(p->w), c->w);
        break;
    default:
        fprintf(stderr, "gx_attach: kind %d cannot parent\n", p->kind);
    }
}

void gx_detach(int64_t parent, int64_t child) {
    HE *p = he_find(parent), *c = he_find(child);
    if (!p || p->dead || !c || c->dead) {
        fprintf(stderr, "gx_detach: dead handle %lld->%lld\n",
                (long long)parent, (long long)child);
        return;
    }
    /* detach never destroys (the protocol's single destruction rule
     * is `destroy` releases) — ref the child so the removal's release
     * leaves it alive on a shim-held ref, dropped by its destroy */
    g_object_ref(c->w);
    switch (p->kind) {
    case K_WINDOW:
        gtk_window_set_child(GTK_WINDOW(p->w), NULL);
        break;
    case K_VBOX:
    case K_HBOX:
        gtk_box_remove(GTK_BOX(p->w), c->w);
        break;
    case K_SCROLLED:
        gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(p->w), NULL);
        break;
    case K_LIST: {
        GtkWidget *w = c->w;
        GtkWidget *row = GTK_IS_LIST_BOX_ROW(w)
            ? w : gtk_widget_get_ancestor(w, GTK_TYPE_LIST_BOX_ROW);
        if (row)
            gtk_list_box_remove(GTK_LIST_BOX(p->w), row);
        break;
    }
    default:
        break;
    }
}

/* ---- pump ---- */
static int wakeflag;

/* wake — any task. The flag covers a nudge landing between pump's
 * drain check and its iteration wait: the next gx_iter then runs
 * nonblocking instead of sleeping on a queued command. */
void gx_wake(void) {
    wakeflag = 1;
    g_main_context_wakeup(NULL);
}

/* one main-context iteration. may_block=0 always returns after
 * dispatching pending sources (pump calls this between Cmd drains so
 * a command burst cannot starve the signal ring); may_block=1 waits
 * for a source — a pending gx_wake forces the nonblocking path. */
void gx_iter(int64_t may_block) {
    if (wakeflag) {
        wakeflag = 0;
        may_block = 0;
    }
    g_main_context_iteration(NULL, may_block != 0);
}

/* ---- test hooks ---- */
typedef struct { int64_t h; char sig[32]; } EmitArgs;
static gboolean emit_cb(gpointer data) {
    g_n_emitcb++;
    EmitArgs *a = data;
    HE *e = he_find(a->h);
    if (!e || e->dead) g_n_hedead++;
    if (e && !e->dead) {
        if (!strcmp(a->sig, "close-request")) {
            gboolean ret = FALSE;
            g_signal_emit_by_name(e->w, "close-request", &ret);
        } else {
            g_signal_emit_by_name(e->w, a->sig);
        }
    }
    free(a);
    return G_SOURCE_REMOVE;
}
/* emit a real GTK signal by handle — deferred onto the GUI thread */
void gx_emit(int64_t h, const char *sig) {
    g_n_invoke++;
    EmitArgs *a = malloc(sizeof *a);
    a->h = h;
    snprintf(a->sig, sizeof a->sig, "%s", sig);
    g_main_context_invoke(NULL, emit_cb, a);
}

/* activate list row idx through the real row-activated signal */
static gboolean row_cb(gpointer data) {
    int64_t *a = data;
    HE *e = he_find(a[0]);
    if (e && !e->dead && e->kind == K_LIST) {
        GtkListBoxRow *r =
            gtk_list_box_get_row_at_index(GTK_LIST_BOX(e->w), (int)a[1]);
        if (r)
            g_signal_emit_by_name(e->w, "row-activated", r);
    }
    free(a);
    return G_SOURCE_REMOVE;
}
void gx_emit_row(int64_t list, int64_t idx) {
    int64_t *a = malloc(sizeof *a * 2);
    a[0] = list;
    a[1] = idx;
    g_main_context_invoke(NULL, row_cb, a);
}
