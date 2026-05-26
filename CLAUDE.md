# Fitness Tracker — iOS App

A SwiftUI iOS client for the Fitness Tracker fitness program platform. Talks to a Nuxt 4 / Postgres backend at `/Users/saulgraves/code/fitness-tracker` (separate repo) over HTTP.

- **Bundle ID:** `me.fitness-app.fitness` (dev-only — see Backlog before TestFlight)
- **Minimum Deployment Target:** iOS 17.6
- **Swift Version:** 5.0
- **Xcode Project:** `FitnessTracker/FitnessTracker.xcodeproj`

## Architecture

- **UI**: SwiftUI with `@Observable` view models (not the older `ObservableObject` pattern). Services and the `APIClient` are also `@Observable` so they can be injected with `.environment(...)`.
- **Persistence**: SwiftData (`@Model` types in `Core/Models/`).
- **Networking**: `Core/Networking/` — `APIClient` + `APIEndpoint` enum. JSON keys are camelCase end-to-end (no snake_case conversion — the server speaks camelCase).
- **Auth**: `Core/Auth/` + `Features/Auth/`. Sign in with Apple via `AuthenticationServices`. Tokens (access + refresh) stored in Keychain via `KeychainService`. `TokenStore` is an `actor` (in-memory access token); `TokenRefresher` is also an `actor` with an in-flight Task pattern to coalesce concurrent 401s.
- **Logging**: OSLog via `Logger.networking`, `Logger.auth`, `Logger.data`, `Logger.app` in `Core/Logging/AppLogger.swift`.
- **Crash/error reporting**: Sentry, configured in `FitnessTrackerApp.init()` (skipped when DSN is the placeholder). User identity is set in `SessionManager` (`SentrySDK.setUser(...)`): user ID at bootstrap/sign-in, enriched with email once `loadProfile()` lands, cleared on sign-out. dSYMs upload to Sentry from a Release-only Run Script build phase using `sentry-cli` (installed via `brew install getsentry/tools/sentry-cli` — it is *not* bundled in the sentry-cocoa SPM artifact); auth via a local `.sentryclirc` (gitignored). The Debug skip is first in the script so dev builds don't even check for the CLI.
- **Config**: `Debug.xcconfig` / `Release.xcconfig` populate `API_BASE_URL` and `SENTRY_DSN` into `Info.plist`. Read via `APIConfig`.

## Server contract

The server is at `/Users/saulgraves/code/fitness-tracker` (Nuxt 4 + h3 + Prisma + Postgres). When adding endpoints or DTOs, mirror the Prisma schema (`prisma/schema.prisma`) and the route handlers under `server/api/`. Wire keys are camelCase. Enums (`SessionStatus`, `ExerciseGroupType`, `Platform`, `PushEnvironment`) are uppercase strings.

## Conventions

- **DTOs vs. Models**: `*DTO` types are wire-format `Codable` structs in `Features/<area>/DTOs/`. `*Model` types are SwiftData `@Model` classes in `Core/Models/`. DTOs convert to models via a `toModel()` extension when persistence is needed.
- **Endpoint additions**: add a case to `APIEndpoint` and a request body struct (also in `APIEndpoint.swift`). Request bodies are `nonisolated struct ... : Encodable, Sendable`.
- **Tests**: under `FitnessTrackerTests/` mirroring source structure. Use `MockAPIClient` and `TestModelContainer` helpers. Use `swift-testing` (`@Test`, `#expect`) — not XCTest.
- **xcconfig URL gotcha**: xcconfig treats `//` as a comment regardless of variable expansion. To embed `//` in a value, use `SLASH = /` then `http:$(SLASH)/host` so the two slashes are never adjacent in the source. Don't use `\/\/` — backslashes pass through literally and percent-encode to `%5C`.
- **Milestone PR/worktree naming**: every PR in the milestone stack uses a consistent integer N across three places: worktree directory `.claude/worktrees/milestone-N-<slug>/`, branch name `milestone-N-<slug>`, and PR title `Milestone N — <title>`. Always pick N first and use it consistently.
- **Commits**: imperative mood, no prefixes. Co-authored-by line for AI-assisted commits.

## Build & test

- Build/run: open `FitnessTracker/FitnessTracker.xcodeproj` in Xcode → ⌘R. Synchronized folders (`PBXFileSystemSynchronizedRootGroup`) auto-include new Swift files.
- Clean build: ⇧⌘K.
- Test: `xcodebuild test` from the terminal, or ⌘U in Xcode.

## Verification workflow

- **Compile check**: run `xcodebuild build` or `xcodebuild build-for-testing` yourself.
- **Test suite**: run `xcodebuild test` yourself (scheme `FitnessTracker`, an iOS Simulator destination) and report results. The previous `ipc/mig server died` conflict with my running sim is resolved.
- **Smoke test**: tell me to run ⌘⇧K then ⌘R in Xcode — I want to keep driving smoke tests myself.

Keep recommending smoke tests in your verification steps.

## Local dev server

Run the server from `/Users/saulgraves/code/fitness-tracker` with `pnpm dev` — it listens on `localhost:3000`, which `Debug.xcconfig` points at.

## Git command conventions

* Never prefix git commands with `cd`.

---

## Backlog

Items deliberately deferred. Roughly ordered by priority within each tier.

### High

- **Reconcile bundle ID before TestFlight.** Server `.env` `NUXT_APPLE_BUNDLE_ID` is currently set to `me.fitness-app.fitness` to match the iOS scaffold's bundle ID, instead of the canonical `me.fitness-app.tracker` (which matches the repo names and test target IDs). Before TestFlight: pick the canonical ID, register the App ID in Apple Developer with Sign in with Apple capability, generate the provisioning profile, and update both the iOS `PRODUCT_BUNDLE_IDENTIFIER` and the server `.env`. Same value also drives APNs topic.
- **App icon design.** `AppIcon.appiconset/Contents.json` declares three appearance variants (universal / dark / tinted) with no `filename` fields and no PNG assets. Provide 1024×1024 PNGs (e.g., `AppIcon-1024.png`, `AppIcon-1024-dark.png`, `AppIcon-1024-tinted.png`) and wire filename references so asset-catalog validation passes. Required before TestFlight.
- **Feedback tab.** Skipped from milestone 2. Web has a full feedback feature: list with addressed/unaddressed filter tabs, submit form with optional screenshot upload (multipart/form-data). iOS port needs `PhotosPicker` for image selection and multipart body construction in `APIClient`.

### Medium

- **DTO decode-time invariant validation.** Several DTOs model server shapes where a payload is only valid if exactly one of a set of optional fields is populated (e.g., `CompletedSetDTO`'s three set-flavor fields: `exerciseSetId` / `programExerciseId` / `adhocExerciseName`). Currently synthesized `Decodable` lets zero or multiple coexist silently. Audit all DTOs with mutually-exclusive optional fields and add a custom `init(from decoder:)` that decodes all properties, then `guard`s the invariant and throws `DecodingError.dataCorrupted` with a clear `debugDescription` on violation. Keeps bad server payloads from flowing into the UI as ambiguous state.
- **Email & Google sign-in providers.** Web supports both. iOS only has Apple. Email auth needs sign-in / sign-up / password-reset forms plus deep-link handling for the email-confirmation redirect. Google sign-in needs the `GoogleSignIn-iOS` SPM dependency, an iOS OAuth client registered in Google Cloud Console (tied to bundle ID), and URL scheme configuration in `Info.plist`.
- **HealthKit integration.** Read workout / body composition signals where useful; write completed workouts as `HKWorkout` entries. Not present on web (web can't access HealthKit).
- **Push notifications.** APNs is server-side scaffolded (`server/utils/apns.ts`, `registerDevice` endpoint exists in iOS scaffold). Need to: register for remote notifications, capture device token, call `registerDevice`, handle notification delivery / deep links.

### Low

- **Calendar strip enhancements.** MVP is a basic week-scrolling carousel. Future polish: month-view zoom, gesture-driven scrubbing, stronger accessibility (VoiceOver labels per day, dynamic type sizing).
