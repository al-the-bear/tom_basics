/**
 * User model interface.
 */
export interface User {
    id: string;
    name: string;
    email: string;
}

/**
 * Admin user with additional permissions.
 */
export interface AdminUser extends User {
    permissions: string[];
}
