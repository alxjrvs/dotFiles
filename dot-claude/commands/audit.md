Perform a thorough code efficiency audit of the current project.

## Scope

Use the code-efficiency-auditor agent to analyze the codebase. Focus on these areas:

1. **Dead code** -- unused exports, unreachable branches, commented-out code, unused dependencies in package.json
2. **DRY violations** -- duplicated logic, copy-pasted patterns that should be abstracted
3. **Orphaned artifacts** -- types with no consumers, routes with no handlers, styles with no references, test files for deleted modules
4. **Complexity** -- functions that do too much, deeply nested logic, god files/modules
5. **Best practices** -- missing error handling, untyped boundaries, implicit any, missing null checks

## Output format

Organize findings by severity:

- **Critical** -- bugs, security issues, or correctness problems
- **Important** -- maintainability issues, significant dead code, major DRY violations
- **Nice-to-have** -- style improvements, minor cleanup opportunities

For each finding, include:
- File path and line number(s)
- What the issue is
- A concrete, actionable recommendation

Do not pad the report with trivial observations. If the codebase is clean, say so.
