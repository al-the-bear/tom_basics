/**
 * Helper utility functions.
 */

function greet(name) {
    return `Hello, ${name}!`;
}

function capitalize(str) {
    if (!str) return str;
    return str.charAt(0).toUpperCase() + str.slice(1);
}

module.exports = { greet, capitalize };
