# Git Guide Mode Design

This document describes the guided mode (`-g` / `--guide`) for git commands in BuildKit.

## Implementation Status

| Component | Status |
|-----------|--------|
| `--guide` flag on all git commands | ✅ Implemented |
| `GuidedMode` utility class | ✅ Implemented |
| `ProjectGroupPicker` for scope selection | ✅ Implemented |
| `gitcommit -g` full flow | ✅ Implemented |
| Other git commands `-g` | ⏳ Pending (flag added, flow not implemented) |

## Overview

Guided mode provides a step-by-step, menu-driven interface for git operations across multi-repo workspaces. It is designed as a **use-case-based expert system** that:

1. **Guides users** through complex git workflows
2. **Previews commands** before execution
3. **Self-documents** through on-screen descriptions and hints
4. **Completes the use case** - flow ends when the intended operation is done

## Flow Structure

### Main Flow vs Sub-Flows

```
┌─────────────────────────────────────────────────────────────────┐
│                      MAIN FLOW                                   │
│  Starts with command intent → Ends with operation complete      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   gitcommit -g                                                   │
│       │                                                          │
│       ├── [Sub-flow] Stage files ──┐                            │
│       │   └── Pick files           │                            │
│       │   └── Return to staging ◄──┘                            │
│       │                                                          │
│       ├── Enter commit message                                   │
│       │                                                          │
│       ├── Choose push options                                    │
│       │                                                          │
│       ├── Preview & Confirm                                      │
│       │                                                          │
│       └── EXECUTE → EXIT (use case complete)                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Key principle:** The main flow leads to completion. Sub-flows (like file selection) return to their parent step when done.

### Flow Types

| Flow Type | Behavior | Example |
|-----------|----------|---------|
| **Main Flow** | Linear progression → Execute → Exit | gitcommit: stage → message → push → done |
| **Sub-Flow** | Complete task → Return to parent | File picker: select → confirm → back to staging step |
| **Optional Branch** | Offer choice that may skip steps | "Skip staging" bypasses file selection |
| **Confirmation Gate** | Preview then Y/n before execution | All commands show final command before run |

## Usage

```bash
# Start guided mode for any git command
gitcommit -g
gitpull -g
gitstatus -g
bk :gitmerge -g
```

---

## Command Flows

### gitstatus -g

**Use case:** View repository status with options to drill down.

**Note:** gitstatus is unique - it's read-only, so it offers follow-up actions.

```
=== Git Status - Guided Mode ===

Pre-flight:
  Repositories: 5 found
  Fetching remote status... (use --no-fetch to skip)

What would you like to see?
  1. Quick overview (default)
  2. Detailed with files
  3. Show stash information
  4. Exit

Choose [1-4]:
```

**After showing status (offers follow-up since gitstatus is read-only):**
```
--- Status Overview ---

  ✓ tom2 (main) - clean, up to date
  ⚠ tom_module_d4rt (main) - 3 modified files
  ✓ tom_module_basics (main) - clean

[Press Enter to exit, or type command to run]

Quick actions:
  c - Start gitcommit -g
  p - Start gitpull -g
  s - Start gitstash -g
  Enter - Exit
```

---

### gitcommit -g

```
=== Git Commit - Guided Mode ===

Repositories with changes:
  • tom_module_d4rt
  • tom_core_kernel

Step 1: What files to stage?
  1. All files (git add -A) [default]
  2. Tracked files only (git add -u)
  3. Already staged only (skip staging)
  4. Select by project scope
  5. Cancel

Choose [1-5]:
```

**If "Select by project scope" selected:**
```
What to include?
  1. All changed projects (complete)
  2. All changed projects (select scope per project)
  3. Select specific projects
  4. Cancel

Choose [1-4]:
```

**Project scope selection (using interact MultiSelect):**
```
Select scope for tom_core_kernel
  (Space to toggle, Enter to confirm)

  [x] Complete project (All files in the project)
  [ ] Code only (bin/ and lib/ folders)
  [ ] Examples (example/ folder)
  [ ] Tests (test/ folder)
```

**Step 2: Commit message:**
```
Step 2: Enter commit message

Commit message: |

Hint: Start with a verb (Add, Fix, Update, Refactor, Remove)
      Keep under 72 characters for subject line
```

**Step 3: Push options:**
```
Step 3: Push options

  1. Commit and push (default)
  2. Commit only (no push)
  3. Amend previous commit
  4. Skip pre-commit hooks

Choose [1-4]:
```

**Step 4: Confirmation:**
```
Commands to execute in each repository:
  git add -A
  git commit -m "Add new feature"
  git push

Repositories: 5 (tom2, tom_module_basics, tom_module_d4rt, ...)

Proceed? [Y/n]:
```

**After execution (main flow complete - exits):**
```
--- Commit Complete ---

Results:
  ✓ [tom2] pushed to origin/main
  ✓ [tom_module_basics] pushed to origin/main
  ✓ [tom_module_d4rt] pushed to origin/main

Done. 3 repositories committed and pushed.
```

---

### gitpull -g

**Use case:** Pull latest changes safely across all repositories.

```
=== Git Pull - Guided Mode ===

Pre-flight check:
  tom2: main (2 commits behind)
  tom_module_basics: main (up to date)
  tom_module_d4rt: feature/test (3 behind, 1 ahead) ⚠

Pull strategy?
  1. Fast-forward only (default, safe)
  2. Allow merge commits
  3. Rebase instead of merge
  4. Stash first, then pull
  5. Cancel

Choose [1-5]:
```

**If conflicts likely:**
```
⚠️  Potential merge conflicts detected:

  tom_module_d4rt:
    - Branch has local commits not pushed
    - May conflict with upstream changes

Options:
  1. Proceed anyway (may fail)
  2. Stash changes first
  3. Abort and review manually
  4. Show diff of local vs remote

Choose [1-4]:
```

---

### gitbranch -g

```
=== Git Branch - Guided Mode ===

What would you like to do?
  1. List all branches
  2. Create new branch
  3. Switch to existing branch
  4. Delete branch
  5. Rename current branch
  6. Track remote branch
  7. Back to main menu

Choose [1-7]:
```

**If "Create new branch" selected:**
```
Enter new branch name: feature/

Hint: Common prefixes:
  feature/  - New functionality
  bugfix/   - Bug fixes
  hotfix/   - Urgent production fixes
  release/  - Release preparation
  chore/    - Maintenance tasks
```

```
Create from:
  1. Current branch (main)
  2. Remote main (origin/main)
  3. Other branch
  4. Specific commit

Choose [1-4]:
```

```
After creating:
  1. Checkout the new branch (default)
  2. Stay on current branch

Choose [1-2]:
```

---

### gittag -g

```
=== Git Tag - Guided Mode ===

What would you like to do?
  1. List existing tags
  2. Create new tag
  3. Delete tag (local and remote)
  4. Push tags to remote
  5. Checkout specific tag
  6. Back to main menu

Choose [1-6]:
```

**If "Create new tag" selected:**
```
Tag type:
  1. Lightweight tag (just a name)
  2. Annotated tag (recommended, includes metadata)

Choose [1-2]:
```

```
Enter tag name: v

Hint: Common formats:
  v1.0.0     - Semantic version
  release-1  - Release identifier
  build-123  - Build number
```

---

### gitsync -g

```
=== Git Sync - Guided Mode ===

Sync performs: stash → fetch → merge → push

Pre-flight check:
  ✓ tom2: clean
  ✓ tom_module_basics: clean
  ⚠ tom_module_d4rt: 3 uncommitted files

Options:
  1. Full sync with stash (default)
  2. Sync without stash (abort if dirty)
  3. Sync without push (pull only)
  4. Custom: choose each step
  5. Cancel

Choose [1-5]:
```

**If "Custom" selected:**
```
Custom sync options:

  [x] Stash uncommitted changes
  [x] Fetch from remote
  [x] Merge changes (ff-only)
  [ ] Prune stale branches
  [x] Pop stash after merge
  [x] Push to remote

Toggle options with number keys, Enter to proceed:
```

---

### gitclean -g

```
=== Git Clean - Guided Mode ===

⚠️  WARNING: This permanently deletes untracked files!

Scan for untracked files?
  1. Preview what would be deleted (safe)
  2. Cancel

Choose [1-2]:
```

**After preview:**
```
Found 15 untracked files:

  src/
    temp.dart
    debug_output.txt
  build/
    (12 files)

Options:
  1. Delete all shown files
  2. Pick files to delete
  3. Delete only files (keep directories)
  4. Delete files and directories
  5. Cancel

Choose [1-5]:
```

---

### gitcheckout -g

```
=== Git Checkout - Guided Mode ===

What would you like to checkout?
  1. Existing branch
  2. New branch from current
  3. Remote branch (create tracking)
  4. Specific tag
  5. Specific commit
  6. Restore file from HEAD
  7. Cancel

Choose [1-7]:
```

**If "Existing branch" selected:**
```
Local branches:
  1. * main (current)
  2.   feature/auth
  3.   feature/dashboard
  4.   bugfix/login

Remote branches:
  5.   origin/feature/api
  6.   origin/release/1.0

Enter number or branch name:
```

---

### gitreset -g

```
=== Git Reset - Guided Mode ===

⚠️  WARNING: Reset can discard work!

What kind of reset?
  1. Mixed (default) - unstage changes, keep working dir
  2. Soft - keep staged and working changes
  3. Hard - discard all changes (DANGER!)
  4. Just unstage specific files
  5. Cancel

Choose [1-5]:
```

**If any reset option selected:**
```
Reset to:
  1. HEAD (current commit)
  2. HEAD~1 (previous commit)
  3. Specific commit
  4. Remote branch state

Choose [1-4]:
```

**If "Hard" selected:**
```
⚠️  DANGER: Hard reset will permanently discard:
  - All uncommitted changes
  - All staged changes
  - Cannot be undone!

Type 'yes' to confirm, or 'n' to cancel:
```

---

### gitprune -g

```
=== Git Prune - Guided Mode ===

This removes stale remote-tracking branches.

Scanning for stale branches...

Remote branches no longer on server:
  origin/feature/old-feature
  origin/bugfix/fixed-issue
  origin/temp-branch

Options:
  1. Remove all stale branches
  2. Pick which to remove
  3. Cancel

Choose [1-3]:
```

---

### gitstash -g

```
=== Git Stash - Guided Mode ===

What would you like to do?
  1. Stash all changes
  2. Stash with message
  3. Stash including untracked files
  4. List existing stashes
  5. Cancel

Choose [1-5]:
```

---

### gitunstash -g

```
=== Git Unstash - Guided Mode ===

Existing stashes:
  0: WIP on main: abc123 Last commit message
  1: feature-backup: def456 Backup before refactor
  2: experiment: ghi789 Testing new approach

What would you like to do?
  1. Apply most recent (stash@{0})
  2. Apply specific stash
  3. Pop (apply and drop) most recent
  4. Drop stash without applying
  5. Cancel

Choose [1-5]:
```

---

### gitcompare -g

```
=== Git Compare - Guided Mode ===

Compare current branch with:
  1. main
  2. origin/main
  3. Another branch
  4. Specific commit
  5. Previous commit (HEAD~1)

Choose [1-5]:
```

**Output format:**
```
How to display differences?
  1. Summary only (files changed)
  2. Statistics (lines added/removed)
  3. Full diff (all changes)
  4. Side-by-side diff

Choose [1-4]:
```

---

### gitmerge -g

```
=== Git Merge - Guided Mode ===

Merge into current branch (main)?
  1. Yes, merge another branch
  2. Abort in-progress merge
  3. Continue after conflict resolution
  4. Cancel

Choose [1-4]:
```

**If merging:**
```
Select branch to merge:
  1. feature/auth
  2. feature/dashboard
  3. origin/main
  4. Enter branch name

Choose [1-4]:
```

```
Merge strategy:
  1. Standard merge (creates merge commit if needed)
  2. Squash (combine all commits into one)
  3. Fast-forward only (fail if not possible)
  4. No fast-forward (always create merge commit)

Choose [1-4]:
```

---

### gitsquash -g

```
=== Git Squash - Guided Mode ===

Squash combines all commits from a branch into one change.

Select branch to squash:
  1. feature/auth (5 commits)
  2. feature/dashboard (12 commits)
  3. Enter branch name

Choose [1-3]:
```

```
After squash:
  1. Auto-commit with message
  2. Leave staged (manual commit later)

Choose [1-2]:
```

---

### gitrebase -g

```
=== Git Rebase - Guided Mode ===

⚠️  WARNING: Rebase rewrites history!
    Only rebase commits not yet pushed.

What would you like to do?
  1. Rebase onto another branch
  2. Interactive rebase (edit commits)
  3. Abort in-progress rebase
  4. Continue after conflict resolution
  5. Skip current commit
  6. Cancel

Choose [1-6]:
```

---

## Navigation Patterns

### Menu Selection

Uses `interact` package's `Select` component:

```
What files to stage?
  > All files (git add -A) [default]
    Tracked files only (git add -u)
    Already staged only
    Select by project scope
    Cancel

Use arrow keys to navigate, Enter to select
```

### Confirmation

Uses `interact` package's `Confirm` component:

```
Proceed? [Y/n]: 
```

- Y or Enter - Confirm
- n - Cancel

### Selection Lists

Uses `interact` package's `MultiSelect` component:

```
Select scope (Space to toggle, Enter to confirm):

  [x] Complete project
  [ ] Code only
  [ ] Examples
  [x] Tests
```

Keys (provided by interact):
- Space - Toggle selection
- Up/Down - Navigate
- Enter - Confirm

### File/Folder Trees

For git operations, use the `ProjectGroupPicker` instead of individual file selection:

```dart
final picker = ProjectGroupPicker(
  workspaceRoot: executionRoot,
  changedProjects: reposWithChanges,
);

final selection = picker.pick();
if (selection == null || selection.isEmpty) {
  // Cancelled
  return true;
}

// Get paths to stage based on selected scopes
final paths = selection.getFilePaths();
```

---

## Implementation Notes

### Library: interact

Guided mode uses the `interact` package for cross-platform interactive prompts:

```dart
import 'package:interact/interact.dart';

// Single select menu
final choice = Select(
  prompt: 'What files to stage?',
  options: ['All files (git add -A)', 'Tracked only', 'By project scope'],
).interact();

// Multi-select with checkboxes
final scopes = MultiSelect(
  prompt: 'Select scope',
  options: ['Complete project', 'Code only', 'Examples', 'Tests'],
  defaults: [true, false, false, false],
).interact();

// Confirmation
final proceed = Confirm(
  prompt: 'Execute commands?',
  defaultValue: true,
).interact();

// Text input
final message = Input(
  prompt: 'Commit message',
).interact();
```

### Project Scopes

For git operations, files are selected by project scope rather than individual files:

| Scope | Folders | Description |
|-------|---------|-------------|
| Complete project | `.` | All files in the project |
| Code only | `bin/`, `lib/` | Source code folders |
| Examples | `example/` | Example code |
| Tests | `test/` | Test files |

### Guided Mode Utilities

Implementation in `lib/src/guided/`:

| File | Purpose |
|------|---------|---|
| `guided_mode.dart` | `GuidedMode` class with menu, multiSelect, confirm, input, showPreview |
| `project_group_picker.dart` | `ProjectGroupPicker` for project scope selection |
| `guided.dart` | Barrel export |

### Usage in Tools

```dart
import '../guided/guided.dart';

Future<bool> _runGuided(String executionRoot, WorkspaceNavigationArgs navArgs) async {
  final guide = GuidedMode();
  
  guide.header('Git Commit - Guided Mode');
  
  // Show menu
  final choice = guide.menu(
    'What files to stage?',
    ['All files', 'Tracked only', 'By project scope'],
  );
  
  if (choice == -1) return true; // Cancelled
  
  // Get commit message
  final message = guide.input('Commit message');
  
  // Show preview and confirm
  guide.showPreview(
    command: 'git commit -m "$message"',
    repositories: reposWithChanges,
  );
  
  if (!guide.confirm('Proceed?')) return true;
  
  // Execute...
}
```

### State Machine

Each guided mode is a state machine:

```
┌──────────────┐
│   Start      │
└──────┬───────┘
       ↓
┌──────────────┐
│ Show Options │
└──────┬───────┘
       ↓
┌──────────────┐     ┌──────────────┐
│ Get Input    │────→│ Validate     │
└──────────────┘     └──────┬───────┘
       ↑                    ↓
       │             ┌──────────────┐
       │             │ Execute/Next │
       │             └──────┬───────┘
       │                    ↓
       │             ┌──────────────┐
       └─────────────│ What Next?   │
                     └──────────────┘
```

### Error Handling

- Git command failures show error and offer retry/skip/abort
- Network failures offer retry with exponential backoff
- Conflict detection shows affected files and offers resolution paths
