// Bundle the language client into a single self-contained extension.js —
// the shipped vsix carries no node_modules and needs no npm at install.
import { build } from 'esbuild';

await build({
  entryPoints: ['src/client.js'],
  bundle: true,
  platform: 'node',
  format: 'cjs',
  outfile: 'dist/extension.js',
  external: ['vscode'],
  logLevel: 'info',
});
