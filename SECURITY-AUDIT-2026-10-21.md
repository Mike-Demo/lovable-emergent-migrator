# Security audit triage — 2026-10-21

Parent: https://github.com/Mike-Demo/lovable-emergent-migrator/issues/1

Issue creation is unavailable in this session. The four entries below contain
ready-to-file issue titles and bodies; no remediation has been implemented.
Evidence is static source inspection, not exploit execution or endpoint probing.
Source links pin the inspected revision.

## Prioritized confirmed backlog

All three findings retain the audit's **medium** severity. They have distinct
root causes, so none are grouped. Copies of the same flaw belong in the same
remediation issue, not separate issues per delivery surface.

| Order | Finding | Reachability, impact, and fix scope |
| --- | --- | --- |
| 1 | Prompt injection through repository metadata | A lower-trust repository author controls inputs consumed across CLI, browser, and MCP prompt generation. The operator must hand the prompt to Emergent; the downstream agent's behavior determines impact, potentially including credential misuse. Fix is bounded to metadata handling but spans multiple generators. |
| 2 | Secret sanitization does not gate export | A normal migration of a repository containing tracked secrets can propagate credentials to the import branch and subsequently Emergent. Push requires operator opt-in; import is a further step. A scan gate is small, but safe untracking, false-positive review, and existing Git history require care. |
| 3 | Destructive reuse of a colliding checkout | Requires a pre-existing local checkout at the basename-derived work directory, from another migration, local state, or a party able to place it there. Reset can destroy local work and optional push targets that checkout's origin. Ownership/origin checks are small and safe, but the local collision precondition makes it less broadly reachable. |

Risk and lower-trust reachability take precedence over fix size; the smallest
patch is therefore not necessarily first. This ordering does not assert that
downstream agent exploitation or either validation lead has been demonstrated.

## 1. Ready-to-file remediation issue

### Title

[security][medium] Fence and sanitize repository metadata in Emergent prompts

### Body

Parent audit: https://github.com/Mike-Demo/lovable-emergent-migrator/issues/1

Priority: 1 of 3 confirmed findings. Severity: medium.
Fingerprint: `emergent-prompt-injection-via-repo-metadata`.

**Evidence**

- [Analyzer input collection](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/mcp/analyze.js#L55-L105)
  retains the package name, raw dependency version strings, and function directory names.
- [Prompt interpolation](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/mcp/analyze.js#L116-L168)
  inserts those values into instruction text, adjacent to instructions to request
  Supabase credentials, without control-character stripping, length caps, or an
  untrusted-data boundary.
- The [browser prompt builder](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/web/index.html#L524-L579)
  and [shell prompt generator](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh#L183-L265)
  perform equivalent interpolation. Repository-authored multiline values can
  become standalone instruction lines in the prompt the operator hands to Emergent.

**Root cause**

Lower-trust repository metadata and trusted agent instructions share the same
unstructured prompt context. No output-boundary sanitization or fencing separates
the two. This is a prompt trust-boundary issue, not demonstrated local code execution.

**Smallest fix**

At every prompt output boundary, sanitize every repository-derived value: strip
CR/LF and other control characters, enforce explicit length caps, and encode or
escape delimiter characters so metadata cannot terminate its own data block.
Place these values only in a clearly fenced block labelled **untrusted repo
metadata**, with trusted instructions outside it telling the agent to treat the
block as data, not instructions. Preserve useful ordinary metadata.

Apply to the linked analyzer, browser, and shell generators and their copies:

- [Web analyzer](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/web/analyze.js)
- [Skill MCP analyzer](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/skills/lovable-emergent-migrator/mcp/analyze.js)
- [Skill web analyzer](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/skills/lovable-emergent-migrator/web/analyze.js)
- [Skill browser generator](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/skills/lovable-emergent-migrator/web/index.html)
- All shell copies listed in remediation issue 2 below.

**Acceptance checks**

- [ ] Package names, dependency versions, function names, and other interpolated
      repo-derived values containing newlines, control characters, oversized
      content, and fence delimiters remain bounded untrusted data on every surface.
- [ ] Ordinary prompts retain their migration instructions and useful metadata.
- [ ] Document that fencing reduces risk but cannot guarantee an LLM will ignore
      adversarial text; do not claim downstream exploitation was validated.

## 2. Ready-to-file remediation issue

### Title

[security][medium] Gate migration commit and push on secret review

### Body

Parent audit: https://github.com/Mike-Demo/lovable-emergent-migrator/issues/1

Priority: 2 of 3 confirmed findings. Severity: medium.
Fingerprint: `cli-secret-sanitize-not-enforced-before-push`.

**Evidence**

- [Tracked-env and secret-pattern scans](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh#L108-L137)
  print warnings without setting a blocking state.
- [Sanitization](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh#L140-L154)
  removes builder artifacts and adds ignore patterns, but does not untrack
  already-tracked env/secret files.
- [Commit and optional push](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh#L268-L297)
  proceed without consulting the scan results. The import branch can therefore
  carry flagged secrets to the third-party import workflow.

**Root cause**

Secret detection is advisory rather than an enforced pre-export gate.
Ignore rules do not remove files already in Git's index.

**Smallest fix**

Retain blocking state for tracked env files and secret-pattern hits. During
sanitization, untrack the flagged env/secret files using `git rm --cached --`
without deleting local copies; ensure later staging cannot silently re-add them.
Abort before commit or push whenever findings exist unless the operator supplies
an explicit `--allow-secrets-reviewed` flag after review. Keep overrides explicit
and warn about residual exposure without printing secret values.

Apply to all four shell entry points:

- [Root CLI](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh)
- [Web download](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/web/migrate-to-emergent.sh)
- [Skill script](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/skills/lovable-emergent-migrator/scripts/migrate-to-emergent.sh)
- [Skill web download](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/skills/lovable-emergent-migrator/web/migrate-to-emergent.sh)

**Acceptance checks**

- [ ] Tracked env files and secret-pattern hits each independently prevent
      commit/push by default, including runs without the push option.
- [ ] Untracking preserves local files and subsequent staging does not re-add them.
- [ ] Clean repositories continue normally; false positives require the explicit
      review override, consistently across all shell copies.
- [ ] Explain that untracking does not purge existing Git history. Previously
      committed credentials require rotation and review of history before sharing;
      a review override must not be described as proof of a secret-free export.

## 3. Ready-to-file remediation issue

### Title

[security][medium] Verify checkout ownership before destructive workdir reuse

### Body

Parent audit: https://github.com/Mike-Demo/lovable-emergent-migrator/issues/1

Priority: 3 of 3 confirmed findings. Severity: medium.
Fingerprint: `cli-destructive-workdir-reuse-on-name-collision`.

**Evidence**

- [Directory selection and reuse](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh#L48-L68)
  derives the work directory from the repository basename. An existing Git
  directory is fetched and force-checked out, then hard-reset without an origin
  comparison or script-ownership marker.
- Subsequent sanitization rewrites files and removes builder artifacts;
  [commit and optional push](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh#L268-L297)
  use that checkout and its own origin. A name collision can discard unrelated
  local changes and target the wrong repository.

**Root cause**

A predictable basename and the presence of a Git directory are treated as proof
that a checkout is script-owned scratch space.

**Smallest fix**

Before any reuse operation, require both an origin URL matching the requested
repository (`git -C "$DIR" remote get-url origin`) and a script-ownership marker.
Create the marker only after a successful fresh clone; do not adopt an existing
directory by adding a marker. On missing marker, mismatched/missing origin, or
verification failure, abort before fetch/checkout/reset/rewrite, or clone into a
fresh unique directory without modifying the existing one. Apply to all four
shell entry points linked in remediation issue 2.

**Acceptance checks**

- [ ] Same-basename repositories with different origins do not reuse a checkout.
- [ ] Unmarked checkouts are untouched even when their origin matches.
- [ ] Verification failures leave existing work and remotes unchanged and do not
      commit or push.
- [ ] A fresh clone receives the marker, and verified script-owned reruns retain
      the intended migration behavior.

## 4. Ready-to-file validation checklist issue

### Title

[security][needs-validation] Audit leads to validate

### Body

Parent audit: https://github.com/Mike-Demo/lovable-emergent-migrator/issues/1

These are unconfirmed leads, not confirmed vulnerabilities. No severity is
assigned. The parent reports two leads; both are included below. Its missing-fact
text ends in literal ellipses, preserved verbatim here. Recover the complete
wording from the audit author before declaring either validation complete.
Do not use real credentials or probe deployed endpoints without authorization.

- [ ] **CLI git clone option injection**
  - Fingerprint: `cli-git-clone-option-injection`.
  - Claimed root cause: the repo argument is accepted verbatim and passed to
    clone without URL/leading-dash validation or an option separator.
  - Static location: [argument parsing and clone invocation](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/migrate-to-emergent.sh#L33-L58).
  - Exact missing fact supplied by the parent:
    > `A demonstrated payload under the script's exact argv layout - git clone --quiet <REPO> <DIR> where DIR is a basename-derived local path that becomes the repository operand once REPO takes option form - that reaches command execution (e.g. via --upload-pack=, -c core.sshCommand=, or protocol.ext) on a named local git version. Blocked by the no-exec…`
  - Validation deliverable: recover the truncated qualification; use an isolated,
    disposable local fixture to record the Git version, exact argv and derived
    destination, and whether a harmless execution marker is reached. Argument
    acceptance alone does not demonstrate command execution.

- [ ] **Unencoded GitHub API path values with caller token**
  - Fingerprint: `github-api-path-injection-with-caller-token`.
  - Claimed root cause: owner, repo, and tree file paths enter token-bearing
    GitHub API URLs without segment encoding; branch alone is encoded.
  - Static locations: [analyzer URL construction](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/mcp/analyze.js#L1-L83)
    and [browser API requests](https://github.com/Mike-Demo/lovable-emergent-migrator/blob/9ec5d38ee7c2d2a10168667582cc3428db560a55/web/index.html#L334-L454).
  - Exact missing fact supplied by the parent:
    > `How Node fetch / the browser WHATWG URL parser and api.github.com normalize the exact crafted strings (encoded dot segments %2e%2e in owner and in tree file paths, '?'/'#' inside the owner capture, duplicate ref query parameters) - i.e., whether any crafted owner/tree-path value actually moves a token-bearing request off the intended /repos/{owner…`
  - Validation deliverable: recover the truncated intended-path condition; record
    runtime versions, parsed URLs, final request targets, normalization behavior,
    and whether token-bearing requests leave the intended repository API scope.
    Use dummy tokens and local request interception first; parser-only results
    do not establish GitHub server behavior or cross-origin token leakage.

For each lead, record supported or rejected status with reproducible evidence,
or leave it open with the exact unresolved fact. Only a validated finding should
receive a separate severity assessment and remediation issue.
