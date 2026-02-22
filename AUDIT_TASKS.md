# Hugora Audit Task Tracker

Last updated: 2026-02-22

Status legend: `TODO` | `IN_PROGRESS` | `BLOCKED` | `DONE`

## Phase 0 - Unblockers

| ID | Pri | Area | Status | Task | Done When |
|---|---|---|---|---|---|
| HUG-AUD-001 | P1 | Correctness | DONE | Fix editor open/save race causing rename test flake/failure. | `EditorStateRenameTests.autoRenameUsesSlugFrontmatterWhenEnabled` passes consistently. |
| HUG-AUD-002 | P1 | CI | DONE | Add regular CI workflow for PRs/pushes (build + tests + lint). | PRs run automated checks without requiring release tags. |
| HUG-AUD-003 | P2 | Tooling | DONE | Ensure lint tool availability in CI and local docs (`swift-format` install/use). | `just lint` works in CI and documented local setup. |

## Phase 1 - Security Hardening

| ID | Pri | Area | Status | Task | Done When |
|---|---|---|---|---|---|
| HUG-AUD-004 | P1 | Security | DONE | Replace string `hasPrefix` path checks with boundary-safe path containment helper. | Paths like `/site2` no longer pass checks for `/site`. |
| HUG-AUD-005 | P1 | Security | DONE | Apply boundary-safe path helper in workspace content dir resolution. | Escaped `contentDir` values cannot break workspace boundaries. |
| HUG-AUD-006 | P1 | Security | DONE | Apply boundary-safe path helper in archetype resolution. | Escaped `archetypeDir` values are rejected safely. |
| HUG-AUD-007 | P1 | Security | DONE | Apply boundary-safe path helper in image path sanitization. | Malicious relative image paths cannot escape post/site roots. |
| HUG-AUD-008 | P1 | Security | DONE | Avoid symlink traversal escapes while scanning content tree. | Symlinks outside workspace are skipped and logged. |
| HUG-AUD-009 | P2 | Security | DONE | Resolve `hugo` executable path safely (avoid blind PATH lookup in production flow). | Executed binary path is validated and deterministic. |
| HUG-AUD-010 | P2 | Security | DONE | Harden CLI installer uninstall/install checks (only replace owned/safe target). | Installer refuses to remove unrelated `/usr/local/bin/hugora` targets. |
| HUG-AUD-011 | P2 | Security | DONE | Scope session file restore to current workspace/bookmark access. | App does not open arbitrary stale paths from `UserDefaults`. |
| HUG-AUD-012 | P1 | Supply Chain | DONE | Pin GitHub Actions to commit SHAs. | Release workflow references immutable action revisions. |
| HUG-AUD-013 | P1 | Supply Chain | DONE | Verify Sparkle archive integrity before extraction (checksum/signature). | Workflow fails fast on unexpected Sparkle artifact hash. |

## Phase 2 - Maintenance and Reliability

| ID | Pri | Area | Status | Task | Done When |
|---|---|---|---|---|---|
| HUG-AUD-014 | P2 | Reliability | DONE | Fix `isLoading` lifecycle so early returns cannot leave loading state stuck. | `isLoading` transitions are correct across all open/refresh/error paths. |
| HUG-AUD-015 | P2 | Product | DONE | Implement `autoSaveEnabled` behavior or remove the setting. | Setting has real effect and tests verify behavior. |
| HUG-AUD-016 | P2 | Parsing | DONE | Replace fragile regex-based Hugo config parser with robust TOML/YAML/JSON parsing. | Real-world Hugo config variants parse reliably in tests. |
| HUG-AUD-017 | P2 | Observability | DONE | Remove silent failures in metadata/frontmatter parse paths; log actionable details. | Failures include actionable logs without crashing UI. |
| HUG-AUD-018 | P3 | Architecture | TODO | Split oversized files by responsibility (`WorkspaceStore`, `EditorView`, `MarkdownStyler`). | Core modules are smaller with focused responsibilities. |
| HUG-AUD-019 | P2 | Testing | TODO | Add regression tests for all audit fixes (security, race, loading, parser). | New tests fail before fixes and pass after fixes. |

## Phase 3 - Performance

| ID | Pri | Area | Status | Task | Done When |
|---|---|---|---|---|---|
| HUG-AUD-020 | P2 | Performance | TODO | Avoid full-file reads during list scan; parse minimal frontmatter window. | Large content trees load faster and with reduced IO. |
| HUG-AUD-021 | P2 | Performance | TODO | Add incremental refresh/file watching instead of full recursive rescan each time. | External changes update sidebar without full reload. |
| HUG-AUD-022 | P2 | Performance | TODO | Move Hugo CLI availability/create operations off main actor. | New post creation does not block UI thread. |
| HUG-AUD-023 | P2 | Performance | TODO | Async image loading/decode pipeline for rendered markdown images. | Scrolling/editing stays responsive with many images. |
| HUG-AUD-024 | P2 | Performance | TODO | Async image paste encoding/writing with UI progress state. | Large paste operations no longer stall typing/UI. |
| HUG-AUD-025 | P3 | Performance | DONE | Restrict scroll observer to current editor scroll view only. | Styling isn’t triggered by unrelated view scroll events. |
| HUG-AUD-026 | P2 | Performance | DONE | Remove duplicate parse triggers (`forceReparse` + debounced pipeline overlap). | Parse workload per keystroke is reduced measurably. |
| HUG-AUD-027 | P3 | Performance | TODO | Restyle only dirty/affected ranges on theme/prefs updates where safe. | Full-doc restyles are avoided for minor updates. |

## Phase 4 - Feature Improvements

| ID | Pri | Area | Status | Task | Done When |
|---|---|---|---|---|---|
| HUG-AUD-028 | P2 | Feature | TODO | Add explicit section picker for new post creation. | User can choose target section before creating post. |
| HUG-AUD-029 | P2 | Feature | DONE | Add auto-rename collision UX (prompt/resolve strategy). | Filename collisions are handled explicitly and safely. |
| HUG-AUD-030 | P3 | Feature | TODO | Add searchable/filterable content list. | Users can quickly locate posts in large sites. |
| HUG-AUD-031 | P3 | Feature | TODO | Add per-workspace preferences (format, section, image paste location). | Settings can differ per site/workspace. |
| HUG-AUD-032 | P3 | Feature | TODO | Add image paste options (resize/compression/naming strategy). | Image paste flow supports size/quality controls. |
| HUG-AUD-033 | P3 | Feature | TODO | Add frontmatter template preview and validation during post creation. | Template issues are shown before file creation. |
| HUG-AUD-034 | P3 | Feature | TODO | Add Hugo command diagnostics panel (stdout/stderr details). | Errors are debuggable without generic alerts only. |
| HUG-AUD-035 | P3 | Security UX | TODO | Add explicit UI warnings for blocked path escapes/config anomalies. | Users get clear warnings when unsafe paths are rejected. |
