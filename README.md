# AFM Local AI

AFM Local AI is a native macOS local AI notebook built on the canonical PRD in `PRD.md` — a local-first notebook for folders, chats, tools, and saved AI work.

The current repo contains a buildable SwiftUI v0 app:

## What's In The Current Version

- **Mode-based shell**: Dashboard, General Chat, and Workspace, with a *structural* layout — Dashboard is a single-column canvas (no sidebar or inspector), General Chat is two columns (sidebar + chat canvas), and Workspace is three columns (adds the inspector). The inspector can therefore never appear outside Workspace.
- **Structural layout**: three zones that rail with native split-view columns — General Chat renders sidebar + canvas, Workspace adds the right inspector, and the header's back/context/action zones are measured live (`GeometryReader`) to align with the sidebar and inspector widths as they resize. The Dashboard is a single full-width canvas (no header band) with a floating capsule island (appearance toggle + status badge) top-right over the hero. A slim footer strip carries the credit link, a native-AFM note, the on-device latency readout (or Mock Mode), and a Ready/Not Ready dot.
- **Dashboard**: AFM Local AI brand block (Apple Foundation Models logo), a spec-pill row (model status, token context, checked-file scope, zero-network note) with an Engine Diagnostics button, actions to start a General Chat or open a Workspace, and a workspaces grid of recent workspaces (file count, a per-workspace gear that opens that workspace's Settings sheet directly, and remove-from-dashboard — removal asks for confirmation, turns the remove cross red on hover, and deletes the workspace's on-disk chunk index).
- **General Chat**: ungrounded but genuinely multi-turn chat persisted as its own context; multiple chats with auto-generated editable titles, New/Delete/Clear. Prompts are built without retrieval, and the on-device model is explicitly told never to invent filenames or citations. Each reply rehydrates the model session from the thread's prior turns; when history approaches the 4096-token window, older turns are auto-summarized so the conversation continues with the same context. Short or single-paragraph replies use inline Markdown (bold, italics, code) rather than an opening heading; `#` headings are reserved for genuinely multi-section answers.
- **Workspace mode**: native folder picker, smart-ignore scanning (`.gitignore` + defaults), and workspace-type classification (General, Code, Obsidian, Research, Data, Mixed). The sidebar shows the Workspace header (gear → Workspace Settings modal sheet with staged Permissions/MCP edits; workspace-kind button → info popover), a tri-state checkbox directory tree (header select-all, a Collapse-all `minus` button beside the checked/total count, and ⌥/⌘-click on any folder collapsing or re-expanding its whole subtree), and the Context & Indexes section (live context-budget meter, chunk/index stats, Rebuild Indexes). Workspaces always open with every file **unchecked** — context is opt-in.
- **Checked-file RAG**: the checkbox tree controls which files enter context. Only checked files are indexed, retrieved, and sent to the model; RAG chat and tools refuse to run when no readable chunks are available. Indexing is ephemeral — the chunk index is rebuilt from the checked files on every chat/tool run, no index status is persisted, and the Dashboard cards show only the file count.
- **Chat-first canvas**: per-context chat histories (auto-title, editable title, Clear/Delete), streaming assistant responses rendered as Markdown, per-message citations, and selectable text. Prior turns are fed back to the model every message (kept verbatim until they'd overflow the context window, then summarized) so chat is contextful across turns and threads. Every message has a Copy button (icon + label, flashes a green checkmark "Copied" on success); assistant responses in Workspace also have a Save button (floppy icon + "Save", flashes "Saved"; duplicate saves of the same message are rejected).
- **Predefined tools** (Summarize, Extract Actions, Organize Files, Explain Codebase, Extract to JSON) run from a two-column ToolCard grid in the Workspace inspector and are routed through the chat transcript, each with a plan and activity timeline (live steps are shown in the transcript while a tool runs, and failures persist as a bubble in chat history). Running a tool never auto-grants permissions: a non-plan tool with missing permissions fails up front with a "Permissions required" notice; plan-only tools (Organize Files) still run to draft a review plan, and its Approve is gated on the Write permission.
- **Plan approval and real file execution**: Organize Files drafts a move plan through the native Apple Foundation Models `Tool` protocol — `FileListerTool` lists the workspace and `OrganizerTool` records one `organize_file` proposal per file (`source` + `destination`, records only, never moves) — collected into the existing `FileOperationPlan` review-card flow; a brace-aware JSON `PlanOperationParser` remains as the fallback when no tool plan arrives (fenced, wall-broken, or bare block). The plan bubble shows a "Proposed moves" review card with one editable destination folder per file (free-form destinations), plus Approve/Reject — Approve is gated on the Write permission. Approving executes real moves with `FileManager` (moves only: creates folders, never deletes or overwrites, skips no-op same-folder moves), logs per-operation outcomes to activity, posts a result bubble, then rescans the workspace, drops moved files from the checked set, and rebuilds the chunk index. Malformed output fails explicitly instead of silently doing nothing, and a note reports any checked file the proposal skipped or omitted. On the on-device 3B model proposals are progressive (roughly one file per run), so you approve a move and re-run for the rest.
- **Right inspector (Workspace only), two stacked panels**: Workbench (two-column ToolCard grid — tap to open a tool modal with info/plan and Run/Close buttons, running-state glow) and Saved Responses (title-only rows, rename, open in a modal detail view). The context budget, index stats, and Rebuild Indexes live in the left sidebar's Context & Indexes section; permissions and MCP live in the Workspace Settings modal sheet.
- **Context budget**: a live `ContextBudgetMeter` in the sidebar's Context & Indexes section derives token occupancy from the checked files (kind-aware density: ~3.2 chars/token for code/data, ~4.0 for prose, minus instructions/response/prompt-overhead reserves) and shows green "fits" / orange "uses the most relevant..." / gray idle — never alarming, and `~` marks estimate-based numbers. In chat the same budget houses the conversation history (General Chat has no checked files, so history can use the whole content budget): recent turns stay verbatim, and once they would exceed it, older turns are summarized so bounded multi-turn chats continue without hitting `contextSizeExceeded`.
- **Permissions**: per-item toggles (Read/Write/Delete/Shell/Network), staged into drafts and committed on Save in the Workspace Settings modal sheet (gear — from the sidebar in Workspace, or from each Dashboard recent-card's gear), with the permission mode derived from the toggles (Reset to Defaults restores Ask Every Time) and stored per workspace path. The pickers hide their labels visually but keep them for VoiceOver.
- **MCP server registry**: a Dashboard-scoped MCP launch button (present in the header action cluster on the Dashboard — MCP is workspace-scoped, so it's hidden in General Chat as irrelevant and in Workspace where the gear → MCP tab already exposes it; the button itself is gated on `mcpTransportReady`, currently false, so it does not appear until the transport layer lands) opens a server manager (add/edit/delete stdio or Streamable HTTP servers, each tagged **Local** or **Remote** with a trust badge and a privacy warning for remote URLs). Remote servers can carry custom header values (e.g. `CONTEXT7_API_KEY`, `X-Goog-Api-Key`), stored in plaintext locally. The Workspace Settings MCP tab lists the registry with per-workspace enable switches, an enabled count, and a remote privacy warning. Transport is configured and persisted but not yet connected — tool discovery and live calls are planned.
- **Appearance**: an appearance toggle (in the header action cluster, or the Dashboard's floating capsule island) cycles System → Light → Dark and persists across launches via `@AppStorage`; the app uses adaptive system colors throughout.
- **Model diagnostics**: the sidebar model status card (Apple Foundation Models logo — the original `foundationmodel-96x96_2x.png` PNG with a gradient-globe fallback — beside the model title "Apple Foundation Models" when on-device — and availability detail, pinned to the bottom of the sidebar in General Chat and Workspace), the Dashboard hero status badge, and the hero spec-pill row's Engine Diagnostics button are clickable and open a Model Diagnostics sheet: availability + plain-language reason, context window in tokens, supported languages, whether the current locale is supported, data source (on-device vs mock), specialized-model availability (e.g. content tagging), and last-checked time. A Re-check button re-runs availability on demand (status was previously fetched once at launch). Users on unsupported Macs see a Mock Mode banner explaining exactly what mock means and how to enable Apple Intelligence.
- **Local intelligence**: `LocalModelClient` protocol with a deterministic mock executor and an Apple Foundation Models adapter (`SystemLanguageModel`, `LanguageModelSession`, streaming) that has been validated on a Mac with Apple Intelligence enabled.
- **Chunking + retrieval**: chunk pipeline with JSON and SQLite FTS-backed metadata store, NaturalLanguage sentence-embedding semantic retrieval blended with FTS and keyword ranking, context-budget selection, and source citations (line/page/slide-aware).
- **File-type extractors**: PDF (PDFKit), DOCX/PPTX (local OOXML reader), Obsidian frontmatter/tags/wikilinks, SQLite schema/rows, and Git snapshots (branch/HEAD/status/diff stats/bounded diffs).
- **Structured-output schemas** for action items, summaries, and file-operation plans (compile-validated value models; live output routing not wired — file-operation proposals are wired through the native FoundationModels `Tool` protocol with a JSON `PlanOperationParser` fallback).
- **Persistence**: `StudioPersistenceStore` snapshot (`studio-state.json`) for recent workspaces, chat threads, saved responses, and task history, plus per-workspace chunk indexes — all under `Application Support/Local AI (AFM)` (a legacy `LocalFMStudio` container is migrated once on first launch).
- **Packaging**: `scripts/build_dev.sh` → `dist/AFM Local AI.app` for development iterations; `scripts/build_production.sh` → `dist/AFM Local AI <version>.dmg` for end-user distribution (version resolved from the newest git tag, ad-hoc or Developer ID signed, drag-to-Applications installer).

## Build

```sh
swift build
```

## Tests

```sh
swift test
```

The suite (310 cases) is green (`0 failures`); the verification log in `TASKS.md` records the resolutions.

## Run

```sh
swift run LocalAI
```

## Build A Dev App

```sh
chmod +x scripts/build_dev.sh
scripts/build_dev.sh release
open "dist/AFM Local AI.app"
```

## Build & Ship A Production .dmg

```sh
scripts/version.sh patch         # 0.1.0 -> 0.1.1 and tags HEAD (major | minor | patch)
scripts/build_production.sh      # -> dist/"AFM Local AI 0.1.1.dmg"
```

- **Versioning**: the newest git tag is the single source of truth — there is no `VERSION` file. `scripts/version.sh` prints the current version, or bumps and tags HEAD when given `major|minor|patch`. Tags are bare `MAJOR.MINOR.PATCH` matching Apple's `CFBundleShortVersionString` rule (exactly three period-separated integers, digits only — no `v` prefix, no `-beta` suffix); malformed tags are rejected. `patch` for bug fixes, `minor` for new features (backwards compatible), `major` for breaking changes (persisted-state format, privileges, permission model). Falls back to `0.1.0` before the first tag.
- **Build number**: `CFBundleVersion` is set automatically to `git rev-list --count HEAD`, a monotonically increasing integer (Apple requires each distributed macOS build to step up).
- **Distribution**: upload the `.dmg` (a single binary file — Dropbox/Attachments safe, no `.app` bundle-flattening). End users open it and drag the app onto `/Applications`, replacing the older copy. There is no auto-update yet — ship a new `.dmg` per release and users re-download.
- **Signing**: the script ad-hoc signs by default. That makes Gatekeeper warn "unidentified developer" (user: right-click → Open, or Security & Privacy → Open Anyway). For clean distribution, export a Developer ID identity and set `DEVELOPER_ID_IDENTITY="Developer ID Application: …" scripts/build_production.sh`; notarization is still required for zero-warning installs (see `TASKS.md`).

## Continuation Files

- `AGENTS.md` explains repo rules and implementation scope.
- `DESIGN.md` defines the product and interface direction.
- `PRD.md` is the single source of product requirements.
- `TASKS.md` tracks completed work, active work, and future phases.

## Current Limitation

The Apple Foundation Models adapter produces real on-device responses (streaming validated; native `Tool`-protocol calls wired for Organize Files move proposals), but the compile-validated structured-output schemas do not route live output for other modes — file plans come from the native `Tool` protocol with a JSON fallback instead, because guided output on the 3B model collapses many files into one operation and mislabels `requiresApproval`. MCP servers can be configured and enabled per workspace, but no transport is connected yet — the registry is local state only (no process launch, no network, no tool discovery). The deterministic mock executor covers UI and dev flows on machines without Apple Intelligence.