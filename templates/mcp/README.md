# MCP secrets — the canonical pattern for a repo

Copy `.mcp.json` and `.env` into a project repo to wire a stdio MCP server with
its secrets resolved [1Password-natively](https://1password.com/blog/securing-mcp-servers-with-1password-stop-credential-exposure-in-your-agent).

How it works:

- **`.mcp.json`** registers the server with `op run --env-file=.env --` as its
  command, so 1Password resolves the references and starts the server with the
  secrets in its process env — for that launch only.
- **`.env`** holds `op://` **references, never values**. It is safe to commit;
  nothing resolved ever touches disk.

Both files carry no secret, so both are committable. The rules:

- Never put a resolved value in either file — only `op://` references.
- Never write a `${VAR}` placeholder into a tracked `.mcp.json`: a later
  `claude mcp add` in that repo can expand it and write the resolved token back
  into the tracked file (Claude Code #18692). `op run --env-file` needs no
  `${VAR}` in `.mcp.json`. The pre-commit hook and `dot doctor` enforce this.

Generate an entry instead of hand-editing:

```sh
dot mcp add example-stdio -- example-mcp-server --stdio   # portable (your op auth)
dot mcp add example-stdio --agent -- example-mcp-server   # headless agent (keychain SA token)
```

For **HTTP** MCP servers there is no process to wrap — use Claude Code's native
`headersHelper` hook pointed at an inline `op read` (see `gh/gh-mcp-auth-header`
in the dotfiles repo), not this template.
