import * as vscode from 'vscode';
import { helloWorld } from './helloWorld';

/**
 * Register all commands for the extension.
 */
export function registerCommands(context: vscode.ExtensionContext) {
    const disposable = vscode.commands.registerCommand('zom-extension.helloWorld', helloWorld);
    context.subscriptions.push(disposable);
}
