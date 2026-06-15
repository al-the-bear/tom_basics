/**
 * Main entry point for the JavaScript test project.
 */

const { greet } = require('./utils/helpers');
const UserService = require('./services/userService');

function main() {
    console.log(greet('World'));
    
    const userService = new UserService();
    console.log(userService.getUser('123'));
}

main();

module.exports = { main };
