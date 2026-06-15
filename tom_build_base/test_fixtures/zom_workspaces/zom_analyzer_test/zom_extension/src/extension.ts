import * as vscode from 'vscode';
import { registerCommands } from './commands/registerCommands';

/**
 * Extension activation function.
 */
export function activate(context: vscode.ExtensionContext) {
    console.log('Zom Extension is now active!');
    registerCommands(context);
}

/**
 * Extension deactivation function.
 */
export function deactivate() {
    console.log('Zom Extension deactivated.');
}
