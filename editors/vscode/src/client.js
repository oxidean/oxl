// oxl language client — spawns `oxl lsp` over stdio and wires the full
// server surface (diagnostics, hover, completion, rename, formatting,
// semantic tokens, watched-file invalidation) into VS Code.
const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

/** @type {LanguageClient | undefined} */
let client;

function activate(context) {
  const config = vscode.workspace.getConfiguration('oxl');
  const command = config.get('oxl.lsp.path', 'oxl');

  client = new LanguageClient(
    'oxl',
    'OXL Language Server',
    {
      command,
      args: ['lsp'],
      transport: TransportKind.stdio,
    },
    {
      documentSelector: [{ language: 'oxl', scheme: 'file' }],
      synchronize: {
        // the server handles workspace/didChangeWatchedFiles for
        // import-graph invalidation
        fileEvents: vscode.workspace.createFileSystemWatcher('**/*.oxl'),
      },
      outputChannelName: 'OXL Language Server',
    }
  );

  context.subscriptions.push(client.start());
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
