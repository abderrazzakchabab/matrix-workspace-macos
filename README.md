# matrix-workspace-macos

A native **macOS client** (SwiftUI + AppKit) for the Matrix Agent Workspace control plane — the desktop GUI analog of [`matrix-workspace-tui`](https://github.com/abderrazzakchabab/matrix-workspace-tui).

It speaks the same control-plane HTTP + SSE contract as the mobile and TUI clients: Matrix-token sign-in, workspaces, rooms, run launch, live run-event streams, GitHub read panels, the write-grant → approval → mutation flow, and the audit trail.

## Repository layout

- `Sources/MatrixWorkspaceCore` — platform-agnostic client library (Swift Package). Models mirror `packages/contracts`, the REST client mirrors `apps/mobile/src/api/control-plane.ts`, and the SSE client mirrors `apps/mobile/src/api/run-events.ts`. Builds and tests on both Linux and macOS.
- `Sources/MatrixWorkspaceApp` — the SwiftUI app shell (macOS 14+), kept in a separate target that only builds where SwiftUI is available.
- `Tests/MatrixWorkspaceCoreTests` — unit tests (models, SSE frame parsing/validation, cookie/401 session semantics, endpoint wiring, stream reconnect/resume) runnable on Linux via `swift test`.

## Building the macOS desktop app

### Prerequisites

- A Mac running **macOS 14 (Sonoma)** or later.
- **Xcode 15** or later, for the Swift toolchain and the macOS SDK. Install it from the Mac App Store, then make sure it is the selected toolchain:

  ```sh
  sudo xcode-select -s /Applications/Xcode.app
  swift --version   # should report Swift 5.9 or later
  ```

### Get the source

```sh
git clone https://github.com/abderrazzakchabab/matrix-workspace-macos.git
cd matrix-workspace-macos
```

### Build, test, and run

```sh
swift build                      # debug build of the core library + app
swift test                       # run the core unit tests
swift run matrix-workspace-macos # launch the app for development
```

`swift run` starts the app as a bare process, which is fine for iterating. On first launch, sign in with your control-plane URL, homeserver URL, and a Matrix access token.

### Package a double-clickable `.app` (ad-hoc signed, local use)

SwiftPM produces a bare executable, not a Finder-launchable app bundle. Create a minimal bundle from a release build:

```sh
swift build -c release
APP=dist/MatrixWorkspace.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/matrix-workspace-macos "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"   # ad-hoc signature
open dist/MatrixWorkspace.app
```

The bundled app is ad-hoc signed and **not** notarized — fine for building and running on your own Mac, but it will not pass Gatekeeper on other machines. Shipping a Developer ID-signed and notarized `.app`/`.dmg` needs an Apple developer account and a release workflow (see Known limitations).

### Linux (core library only)

The platform-agnostic core and its tests also build on Linux for CI and headless use (Swift 6.x via [swiftly](https://swift.org/swiftly)):

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
