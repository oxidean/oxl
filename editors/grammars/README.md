# @oxidean/shiki-oxl

Shiki / TextMate grammar for the [oxl](https://github.com/oxidean/oxl)
language. Published per oxl release — `@oxidean/shiki-oxl@<ver>` means
"the grammar as of oxl `v<ver>`".

The source of truth is `oxl.tmLanguage.json` in
[`oxidean/oxl`](https://github.com/oxidean/oxl/tree/main/editors/grammars).
Do not edit the published copies downstream; consume the package.

## Install

### Release tarball (recommended — no auth)

Every oxl toolchain release attaches `oxidean-shiki-oxl-<ver>.tgz` (and a
fixed-name `shiki-oxl.tgz` for `releases/latest`):

```bash
bun add "@oxidean/shiki-oxl@https://github.com/oxidean/oxl/releases/download/v0.14.1/oxidean-shiki-oxl-0.14.1.tgz"
```

npm/pnpm/yarn accept the same URL form. Bun pins the URL and records
integrity in `bun.lock`.

### GitHub Packages (semver ranges)

`npm.pkg.github.com` requires authentication for **all** installs, even
on public packages. Map the scope and provide a token with `read:packages`:

```ini
# .npmrc (project) — @oxidean/* resolves to GitHub Packages
@oxidean:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}
```

```bash
npm install @oxidean/shiki-oxl
```

In GitHub Actions, `NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` with
`packages: read` works for same-org packages.

## Use

Bundled/browser consumers (Vite, Astro) import the raw grammar:

```ts
import grammar from "@oxidean/shiki-oxl/grammar.json";
// or, for the Shiki lang object (lowercase name, no embedded langs):
import oxl from "@oxidean/shiki-oxl";

const highlighter = await createHighlighter({
  langs: [oxl],
  themes: ["github-dark"],
});
```

Node-side consumers can `import oxl from "@oxidean/shiki-oxl"` directly —
`index.mjs` loads the grammar and exports it with `name: "oxl"` and
`embeddedLangs: []`.
