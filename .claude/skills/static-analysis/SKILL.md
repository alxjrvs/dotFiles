# Static Analysis

A comprehensive static analysis toolkit with CodeQL, Semgrep, and SARIF parsing for security vulnerability detection.

Based on the Trail of Bits Testing Handbook.

## Sub-skills

This skill contains three specialized tools:

- **codeql/** - Deep security analysis with taint tracking and data flow (see `codeql/SKILL.md`)
- **semgrep/** - Fast pattern-based security scanning (see `semgrep/SKILL.md`)
- **sarif-parsing/** - Parse and process SARIF results from static analysis tools (see `sarif-parsing/SKILL.md`)

## When to Use

Use `/static-analysis` when you need to:
- Perform security vulnerability detection on codebases
- Run CodeQL for interprocedural taint tracking and data flow analysis
- Use Semgrep for fast pattern-based bug detection
- Parse SARIF output from security scanners

Read the relevant sub-skill's SKILL.md for detailed instructions on each tool.
