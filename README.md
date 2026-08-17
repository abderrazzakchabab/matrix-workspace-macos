# matrix-workspace-macos

A native **macOS client** (SwiftUI + AppKit) for the Matrix Agent Workspace control plane — the desktop GUI analog of [`matrix-workspace-tui`](https://github.com/abderrazzakchabab/matrix-workspace-tui).

It speaks the same control-plane HTTP + SSE contract as the mobile and TUI clients: Matrix-token sign-in, workspaces, rooms, run launch, live run-event streams, GitHub read panels, the write-grant → approval → mutation flow, and the audit trail.

## Repository layout

- `Sources/MatrixWorkspaceCore` — platform-agnostic client library (Swift Package). Models mirror `packages/contracts`, the REST client mirrors `apps/mobile/src/api/control-plane.ts`, and the SSE client mirrors `apps/mobile/src/api/run-events.ts`. Builds and tests on both Linux and macOS.
- `Sources/MatrixWorkspaceApp` — the SwiftUI app shell (macOS 14+), kept in a separate target that only builds where SwiftUI is available.
- `Tests/MatrixWorkspaceCoreTests` — unit tests (models, SSE frame parsing/validation, cookie/401 session semantics, endpoint wiring, stream reconnect/resume) runnable on Linux via `swift test`.

## Build & test

**macOS** (Xcode 15+ / Swift 5.9+):

```sh
swift build
swift test
swift run matrix-workspace-macos
```

**Linux** (core library only; Swift 6.x via [swiftly](https://swift.org/swiftly)):

```sh
swift build
swift test
```

CI runs the Linux core tests and builds the full app on both Intel and Apple Silicon macOS runners (`.github/workflows/ci.yml`).

## Control-plane contract

The authoritative client contract lives in [`abderrazzakchabab/matrix-agent-workspace`](https://github.com/abderrazzakchabab/matrix-agent-workspace) (branch `main`):

- `apps/mobile/src/api/control-plane.ts` — REST surface and cookie/session semantics.
- `apps/mobile/src/api/run-events.ts` — SSE framing, validation, resume-from-`after`, terminal-event set, reconnect/backoff.
- `packages/contracts/src/{events,run,github,errors}.ts` — wire types.

Key semantics mirrored here:

- `POST /api/auth/matrix/session` returns a `Set-Cookie` session cookie; every authenticated request sends it as a `Cookie` header, and any `401` clears the session and triggers the `onUnauthorized` callback.
- Run events stream from `GET /api/runs/:id/events?after=N` (with a `Last-Event-ID` header on resume); only digit-only `id`s, `runId`-matching, sequence-consistent events are accepted; the stream stops at `run.{completed,partial,failed,cancelled}` and reconnects with exponential backoff + jitter otherwise.
- GitHub write scope serializes to `issues:write` / `pull_requests:write`; mutation enqueue is 202-new vs 200-replay.
- There is **no** `GET /api/workspaces` endpoint — workspaces are create-only, so the app persists created workspaces locally.

## Known limitations (follow-ups)

- **Run events are not streamed incrementally.**`RunEventStream` uses `URLSession.data(for:)` so the whole frame batch arrives when the SSE response ends (at the terminal event), rather than event-by-event. Apple platforms can be switched to `URLSession.bytes(for:)` for live streaming; the shared parse/validate/reconnect logic already takes a byte decoder and would be unchanged.
- **Release packaging is not wired yet.** Producing a signed/notarized `.app`/`.dmg` requires an Apple developer account and a release workflow — not yet added.
- The GitHub read panel needs a GitHub App installation ID; the OAuth/device-flow wiring (`/api/github/oauth/*`) is not surfaced in the UI yet.
