Scaffold a new project in the current directory using my standard conventions.

## Steps

1. Run `bun init` to initialize the project
2. Set up TypeScript with strict mode enabled (`"strict": true` in tsconfig.json, plus `noUncheckedIndexedAccess`, `noUnusedLocals`, `noUnusedParameters`)
3. Create a `.editorconfig` with these settings:
   - root = true
   - 2-space indentation for all files
   - LF line endings
   - UTF-8 charset
   - Trim trailing whitespace
   - Insert final newline
4. Create a `CLAUDE.md` with project-specific instructions (build/test/lint commands, architecture notes, coding conventions). Keep it minimal and accurate to what actually exists.
5. Set up prettier (`.prettierrc` with 2-space tabs, no semicolons, single quotes) and eslint (`eslint.config.ts` with TypeScript support)
6. Install dev dependencies: `bun add -d prettier eslint @eslint/js typescript-eslint`
7. Initialize git with `git init` and configure the conventional commit template: `git config commit.template ~/.gitmessage`
8. Add a minimal `.gitignore` for node_modules, dist, and .env files

## Principles

- Keep it minimal. Only add what is needed right now.
- Functional patterns over class-based.
- No frameworks or libraries unless the user specifies them.
- The result should be a clean, working starting point — not a boilerplate graveyard.
