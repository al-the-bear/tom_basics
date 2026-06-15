/**
 * User service for managing users.
 */

class UserService {
    constructor() {
        this.users = new Map();
    }

    getUser(id) {
        return `User: ${id}`;
    }

    addUser(id, name) {
        this.users.set(id, name);
    }
}

module.exports = UserService;
