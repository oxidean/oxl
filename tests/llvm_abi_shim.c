/* tests/llvm_abi_shim.c — ABI tripwire for the LLVM lane (L1).
 * Every probe reads an oxl boundary type through rt.h field offsets,
 * compiled by the same toolchain that compiles the emitted .ll. If
 * the IR's boundary type decls (%OxlStr/%RtSlice/%RtFnv) drift from
 * rt.h's field order/width, these reads land on the wrong fields and
 * the fixture's asserts fail loudly. */
#include "../runtime/rt.h"

/* OxlStr {p, n}: length in the thousands, byte sum in the units — a
 * p/n swap reads a pointer as a length and detonates the checksum. */
int64_t abi_probe_str(OxlStr s) {
    int64_t v = s.n * 1000000;
    for (int64_t i = 0; i < s.n; i++)
        v += (unsigned char)s.p[i];
    return v;
}

/* RtSlice {ptr, len, cap, heap} of i64 elements: every field rides
 * the encoding, and the element walk catches a ptr-field drift. */
int64_t abi_slice_len(RtSlice s) { return s.len; }
int64_t abi_slice_cap(RtSlice s) { return s.cap; }
int64_t abi_slice_heap(RtSlice s) { return s.heap; }
int64_t abi_slice_sum(RtSlice s) {
    int64_t t = 0;
    const int64_t *ip = (const int64_t *)s.ptr;
    for (int64_t i = 0; i < s.len; i++)
        t += ip[i];
    return t;
}

/* >16B aggregate return: clang lowers a 32-byte RtSlice through the
 * hidden sret pointer (x8 on arm64, rdi slot on SysV); an IR call site
 * spelled as a direct %RtSlice return expects x0-x3 registers instead
 * and the callee stores its result through garbage. The returned
 * header + elements must decode correctly on every platform. */
RtSlice abi_ret_slice(int64_t n) {
    static int64_t backing[8];
    for (int64_t i = 0; i < n && i < 8; i++)
        backing[i] = i * 7;
    RtSlice s = { backing, n, n, 0 };
    return s;
}

/* RtFnv {env, fp}: the call only lands if env and fp stay unswapped;
 * fp's ABI sig is (void *env, int64_t x) -> int64_t. */
typedef int64_t (*abi_fnv_fp)(void *, int64_t);
int64_t abi_probe_fnv(RtFnv f, int64_t x) {
    return ((abi_fnv_fp)f.fp)(f.env, x);
}

/* RtIface {data, vtab}: vtab[i] is (void *data, args...) — tag takes
 * no args, so slot 0 is (void *data) -> int64_t. Iface values cannot
 * cross FFI by value (the checker explodes the pair into two args),
 * so the pair rides a []Speaker slice: the element stride exercises
 * the full RtIface layout — a swapped pair reads the object as a vtab
 * array and the call lands on garbage. */
int64_t abi_probe_ifaces(RtSlice s) {
    const RtIface *a = (const RtIface *)s.ptr;
    return ((int64_t (*)(void *))a->vtab[0])(a->data);
}
