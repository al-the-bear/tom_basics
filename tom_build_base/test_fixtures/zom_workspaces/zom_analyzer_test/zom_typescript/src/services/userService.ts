import { User } from '../models/user';

/**
 * Service for managing users.
 */
export class UserService {
    private users: Map<string, User> = new Map();

    /**
     * Add a user to the service.
     */
    addUser(user: User): void {
        this.users.set(user.id, user);
    }

    /**
     * Get a user by ID.
     */
    getUser(id: string): User | undefined {
        return this.users.get(id);
    }

    /**
     * Get all users.
     */
    getAllUsers(): User[] {
        return Array.from(this.users.values());
    }
}
