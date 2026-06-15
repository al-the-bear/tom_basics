/**
 * Main entry point for the TypeScript test project.
 */

import { User } from './models/user';
import { UserService } from './services/userService';

function main(): void {
    const userService = new UserService();
    
    const user: User = {
        id: '1',
        name: 'Test User',
        email: 'test@example.com'
    };
    
    userService.addUser(user);
    console.log('User added:', userService.getUser('1'));
}

main();

export { main };
