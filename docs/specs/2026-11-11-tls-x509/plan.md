# TLS/x509 — Stage Plan

Spec: `shape.md`. Contracts: `items/x509-trust.md`,
`items/tls13-wire.md`, `items/tls-api.md`. Working artifacts:
WI-0009 under `.ox-agent/work/`. Stages are sequential unless marked
parallel-ok. Each lands as a PR through the review loop; every stage
lands with the suite green. Automatic reviews are disabled repo-wide
— request a pass manually with `@coderabbitai review` on each stage
PR after pushing the head you want verdicted, and again after the
last fix commit.

- [ ] **L0 — spec** — *(this PR)* — this directory, WI-0009
      artifacts, ADR-0012 for the spec-level forks.
- [ ] **L1 — entropy + hash ground.** `rt_csrand` in rt.c
      (getrandom/`arc4random_buf`/`BCryptGenRandom`, built under
      `-DOXL_CRYPTO` — driver `needs_crypto` scan on `rt_csrand`
      + `-lbcrypt` on Windows only; TLS itself is pure .oxl and
      needs no rt symbols, so the gate names the entropy feature); `std/crypto/rand` (`bytes(n)
      -> [own []byte, err]`, `fill(b) -> err`); `std/crypto/sha512`
      (`new`/`sum512`/`sum384`/`hexdigest`, `hash.Hash` impl);
      `std/crypto/hkdf` (`extract`/`expand`/`expand_label` over
      `hash.Hash`). `math/rand`'s header grows one line naming it
      non-cryptographic and pointing at `crypto/rand`.
      `tests/crypto_rand_test.oxl` (test_csrand — nonzero fill, two
      draws differ, `fill` honors len), `tests/sha512_test.oxl`
      (test_sha512, test_sha384, test_hmac_sha512 — NIST + RFC 4231
      vectors), `tests/hkdf_test.oxl` (test_hkdf — RFC 5869 cases
      1–3 incl. the expand_label unit against a computed-by-hand
      vector). Wired into `tests/run.sh` as `== oxl test: tls
      ground (l1) ==`.
      Exit: vectors green on all three CI legs; `bcrypt` link only
      when emitted text names the extern.
- [ ] **L2 — AEAD ciphers.** `std/crypto/aes` (AES-128/192/256 key
      expansion + *encrypt-only* block — GCM never decrypts);
      `std/crypto/aesgcm` (`seal(key,iv,aad,pt)`/`open(...)`
      AEAD, GHASH over GF(2^128) in i64 hi/lo pairs, tag check in
      one place); `std/crypto/chacha20poly1305` (RFC 8439:
      chacha20 block + poly1305 over 5×26-bit limbs + the AEAD
      composition). `tests/aesgcm_test.oxl` (test_aes_block —
      FIPS-197 + NIST SP 800-38A vectors; test_gcm — NIST GCM
      vectors incl. tampered-tag rejection), `tests/chacha_test.oxl`
      (test_chacha20, test_poly1305, test_aead — RFC 8439 §2.8
      vectors + a wrong-tag reject). Perf gate: seal/open
      of a 4 MiB buffer sustains ≥ 5 MiB/s (loose bound, asserted
      by wall clock).
      Wired `== oxl test: aead (l2) ==`. *Parallel-ok with L1.*
- [ ] **L3 — `bignum` + `rsa` verify.** `std/crypto/bignum`
      (unsigned-magnitude over i64 limbs, base ≤2^26 so schoolbook
      products + accumulators stay < 2^63; `mod`/`modmul`/
      `modexp`/`modinv`/`cmp`; documented "crypto-internal
      building block — API may churn", public only because the
      language has no internal-package rule).
      `std/crypto/rsa`: DER public-key decode (RSAPublicKey SEQ of
      two INTEGERs), PKCS#1 v1.5 verify (EMS A unwrap, DigestInfo
      prefix table sha256/384/512 — sha1/md5 absent by design) and
      PSS verify (MGF1, salt-len recover, trailer `0xbc`).
      `tests/bignum_test.oxl` (test_modmul/test_modexp/test_modinv —
      known-answer + Fermat cross-checks), `tests/rsa_test.oxl`
      (test_rsav15/test_rsapss — checked-in signatures minted by
      `scripts/gen_tls_fixtures.sh` incl. bad-padding rejects).
      Perf gate: RSA-4096 verify < 250 ms on the slowest CI leg.
      Wired `== oxl test: bignum+rsa (l3) ==`. *Depends on L1
      (sha512 for sha384/512 sigs).*
- [ ] **L4 — curves.** `std/crypto/x25519` (RFC 7748 Montgomery
      ladder; ref10-style 10-limb i64 field, `scalarmult(sk,pk)`
      public surface only), `std/crypto/nistec` covering P-256 *and*
      P-384 (prime-field ops on L3's bignum, scalar-mul ECDH,
      ECDSA verify, SEC1 uncompressed-point decode), `std/crypto/
      ed25519` (RFC 8032 verify-only — shares the 25519 field with
      x25519, Edwards point ops, SHA-512 from L1).
      `tests/x25519_test.oxl` (test_x25519 — RFC 7748 §5.2 vectors
      + ECDH symmetry), `tests/nistec_test.oxl` (test_ecdh_p256/
      p384, test_ecdsa — known-answer verify + tamper reject),
      `tests/ed25519_test.oxl` (test_ed25519 — RFC 8032 test 1–3).
      Perf gate: x25519 < 50 ms, ECDSA-P256 verify < 150 ms per op.
      Wired `== oxl test: curves (l4) ==`. *Depends on L1, L3.*
- [ ] **L5 — `std/crypto/x509`.** Contract `items/x509-trust.md`:
      DER reader (unexported), `parse_cert`, `Cert` struct, chain
      build + verify (`verify(leaf, untrusted, roots, name, at)`),
      `Roots` pool (`load_pem`, `append`, `load_system_roots` —
      env override → POSIX paths → `security`/`powershell` exec),
      `match_hostname`. Fixtures under `tests/fixtures/x509/`
      minted once by `scripts/gen_tls_fixtures.sh` (openssl: root,
      intermediate, leaves — rsa/ecdsa/ed25519 keys, expired,
      wrong-name, wildcard, sha1-signed, untrusted-root cases) and
      checked in — the suite never execs openssl.
      `tests/x509_test.oxl` (test_parse, test_chain_ok,
      test_expired, test_bad_name, test_wildcard, test_untrusted,
      test_bad_ca, test_sha1_reject). `tests/x509_env_test.oxl`
      (test_env_file, test_env_dir, test_env_bad_path_fails) —
      run.sh invokes it three ways since a program can't setenv:
      with `OXL_SSL_CERT_FILE`/`OXL_SSL_CERT_DIR` pointed at the
      fixture bundle and with a bogus path asserting `err_roots`
      (env beats store is the pinned order, so the assertions hold
      on every leg regardless of the host's roots). Wired
      `== oxl test: x509 (l5) ==`.
      *Depends on L1, L3, L4.*
      Exit: every fixture asserts its pinned verdict; env-override
      precedence proven in-suite.
- [ ] **L6 — `std/net/tls`.** Contract `items/tls13-wire.md` +
      `items/tls-api.md`: record layer (fragment cap, AEAD nonce =
      iv ^ seq, inner-type strip), handshake state machine
      (ClientHello → HRR≤1 → server flight → CertificateVerify →
      Finished), key schedule over hkdf, `Config`/`Conn`/`dial`/
      `client`, close_notify/`io.eof` mapping, NST consume-ignore,
      KeyUpdate consume + reply. `tests/tls_keys_test.oxl`
      (test_keyschedule — RFC 8448 §3 trace: feed the published
      server flight + the published ECDHE shared secret, assert
      the derived handshake/app traffic keys equal the published
      values; test_record — AEAD round-trip with fixed keys).
      `tests/tls_handshake_test.oxl` (test_handshake_replay —
      checked-in server flight fixture → Finished verifies and the
      Conn reads the fixture's encrypted app data).
      `== tls interop ==` lane behind `command -v openssl`:
      `openssl s_server` + generated CA → `tls.dial` with the CA in
      `roots` performs a real handshake, http GET round-trips; a
      self-signed leaf without the root fails `err_root`; a
      wrong-name leaf fails `err_name`. Skips cleanly where openssl
      is absent (node-gate precedent).
      Exit: replay + interop green; handshake crypto < 1 s end to
      end on CI.
- [ ] **L7 — https + closeout.** `std/net/http`: `Url.secure`,
      `https://` in `parse_url` (port 443), `Client.tlscfg`,
      `secure` → `tls.dial_timeout` (with `tlscfg.server_name`
      defaulted to the URL host; ALPN `["http/1.1"]`).
      `tests/https_test.oxl` (test_https_get — interop lane's
      s_server; test_https_bad_cert — root not trusted → err;
      test_https_wrong_name; parse-level: test_url_https). Docs:
      `docs/tls.md` (surface, trust-root resolution order, err
      taxonomy, side-channel posture per shape §Risk, non-goals +
      their triggers); `parked-stdlib.md`/`parked.md` drop the
      `crypto/tls`/`x509`/asymmetric rows and record what moved to
      live triggers (TLS server, resumption, revocation, constant-
      time pass); `http.oxl` header's "HTTPS stays parked" line
      updated; plan markers `[done]`; WI-0009 → shipped.

## Sequencing

L1 first (everything hashes or draws entropy). L2 parallel-ok with
L1 (no dependency). L3 then L4 (x509 needs every signature scheme;
curves reuse L3's bignum for the prime fields). L5 assembles the
trust story; L6 is the wire — each retires a real risk before the
next spends it. L7 is deliberately thin: one seam in `http` plus
the closeout, so the https diff stays reviewable on its own.

## Parking rules (new triggers this spec creates)

- TLS server (`tls.listen`/`accept`) — trigger: first serving
  consumer needing inbound TLS.
- TLS 1.2 fallback — trigger: first consumer hitting a 1.2-only
  endpoint.
- Session resumption / PSK — trigger: measured reconnect cost on a
  real workload.
- Client certs (mTLS) — trigger: first consumer needing mutual
  auth; brings the *signing* surface back into scope with it.
- Revocation (OCSP/CRL) — trigger: first consumer needing
  revocation proof.
- Constant-time pass — trigger: first server-side or signing
  consumer (today's client posture is documented, not claimed).
- Bundled root list — trigger: first consumer on a platform image
  with no store and no way to set the env override.
