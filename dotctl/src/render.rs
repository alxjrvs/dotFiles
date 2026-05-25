// render — process chezmoi-style `{{ op "op://Vault/Item/field" }}`
// templates by resolving each reference via the 1Password CLI.
//
// CLI: `dotctl render <template> > <destination>` — writes the resolved
// content to stdout; the caller redirects. Stdout (not destination
// argument) keeps the secret-handling story shell-Unix-y and avoids
// dotctl owning a "write secret to disk" code path of its own.
//
// Fails loudly on the FIRST missing ref — never produces a
// partially-rendered output. Each unique reference is resolved once
// even if it appears multiple times.

use anyhow::{Context, Result};
use regex::Regex;
use std::io::Write;
use std::path::Path;
use std::process::Command;
use std::sync::LazyLock;

// Whitespace-tolerant: `{{ op "op://..." }}` / `{{op "op://..."}}` /
// `{{   op  "op://..."   }}` all match. Captures the op:// reference
// (without quotes).
static OP_TEMPLATE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"\{\{\s*op\s+"(op://[^"]+)"\s*\}\}"#).unwrap()
});

pub trait OpResolver {
    fn resolve(&self, reference: &str) -> Result<String>;
}

pub struct OpCli;

impl OpResolver for OpCli {
    fn resolve(&self, reference: &str) -> Result<String> {
        let output = Command::new("op")
            .arg("read")
            .arg(reference)
            .output()
            .context("failed to invoke `op read` — is 1Password CLI installed and signed in?")?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            anyhow::bail!("op read {reference} failed: {stderr}");
        }
        let secret = String::from_utf8(output.stdout)
            .context("op read returned non-utf8")?;
        // `op read` appends a trailing newline; the template expects only the value.
        Ok(secret.trim_end_matches('\n').to_string())
    }
}

pub fn run(path: &Path) -> Result<()> {
    let template = std::fs::read_to_string(path)
        .with_context(|| format!("read template {}", path.display()))?;
    let rendered = render_with(&template, &OpCli)?;
    std::io::stdout().write_all(rendered.as_bytes())?;
    Ok(())
}

pub fn render_with<R: OpResolver>(template: &str, resolver: &R) -> Result<String> {
    // Resolve up front and dedupe so a missing ref aborts BEFORE any
    // substitution happens — no partial-render leaks.
    let mut substitutions: Vec<(String, String)> = Vec::new();
    for cap in OP_TEMPLATE.captures_iter(template) {
        let full = cap.get(0).unwrap().as_str().to_string();
        let reference = cap.get(1).unwrap().as_str();
        if substitutions.iter().any(|(m, _)| m == &full) {
            continue;
        }
        let value = resolver
            .resolve(reference)
            .with_context(|| format!("resolve {reference}"))?;
        substitutions.push((full, value));
    }
    let mut result = template.to_string();
    for (placeholder, value) in &substitutions {
        result = result.replace(placeholder, value);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::collections::HashMap;

    struct MockResolver(HashMap<String, String>);

    impl OpResolver for MockResolver {
        fn resolve(&self, reference: &str) -> Result<String> {
            self.0
                .get(reference)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("not in mock: {reference}"))
        }
    }

    fn mock(pairs: &[(&str, &str)]) -> MockResolver {
        MockResolver(
            pairs
                .iter()
                .map(|(k, v)| ((*k).to_string(), (*v).to_string()))
                .collect(),
        )
    }

    #[test]
    fn basic_substitution() {
        let tmpl = r#"token={{ op "op://Personal/foo/credential" }}"#;
        let r = mock(&[("op://Personal/foo/credential", "abc123")]);
        assert_eq!(render_with(tmpl, &r).unwrap(), "token=abc123");
    }

    #[test]
    fn whitespace_tolerance() {
        let r = mock(&[("op://x", "Y")]);
        assert_eq!(render_with(r#"a={{op "op://x"}}"#, &r).unwrap(), "a=Y");
        assert_eq!(
            render_with(r#"a={{    op  "op://x"   }}"#, &r).unwrap(),
            "a=Y"
        );
    }

    #[test]
    fn multiple_refs_resolve_once_per_unique() {
        struct Counted {
            inner: MockResolver,
            calls: Cell<u32>,
        }
        impl OpResolver for Counted {
            fn resolve(&self, r: &str) -> Result<String> {
                self.calls.set(self.calls.get() + 1);
                self.inner.resolve(r)
            }
        }
        let c = Counted {
            inner: mock(&[("op://x", "Y")]),
            calls: Cell::new(0),
        };
        let tmpl = r#"a={{ op "op://x" }} b={{ op "op://x" }}"#;
        assert_eq!(render_with(tmpl, &c).unwrap(), "a=Y b=Y");
        assert_eq!(c.calls.get(), 1);
    }

    #[test]
    fn no_template_pass_through() {
        let tmpl = "no templates here\n";
        let r = mock(&[]);
        assert_eq!(render_with(tmpl, &r).unwrap(), tmpl);
    }

    #[test]
    fn missing_ref_fails_loudly_with_reference_in_error() {
        let tmpl = r#"x={{ op "op://nowhere/foo/credential" }}"#;
        let r = mock(&[]);
        let err = render_with(tmpl, &r).unwrap_err();
        let msg = format!("{err:#}");
        assert!(
            msg.contains("op://nowhere/foo/credential"),
            "expected ref in error, got: {msg}"
        );
    }

    #[test]
    fn does_not_match_non_op_templates() {
        // Other template-shaped content (env, var, etc.) must pass through untouched.
        let tmpl = "{{ env \"FOO\" }} and {{ var }} and {{ op_lookalike }}";
        let r = mock(&[]);
        assert_eq!(render_with(tmpl, &r).unwrap(), tmpl);
    }

    #[test]
    fn does_not_match_non_op_uri_scheme() {
        // The regex anchors on `op://` — `vault://...` shouldn't match.
        let tmpl = r#"x={{ op "vault://nope" }}"#;
        let r = mock(&[]);
        // No match → no resolution attempt → template unchanged.
        assert_eq!(render_with(tmpl, &r).unwrap(), tmpl);
    }
}
