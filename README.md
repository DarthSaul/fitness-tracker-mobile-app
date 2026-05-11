# Fitness Tracker — iOS

![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)
![iOS](https://img.shields.io/badge/iOS-17.6%2B-blue.svg)
![Platform](https://img.shields.io/badge/platform-iOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A native SwiftUI iOS client for the Fitness Tracker platform — browse programs, run live workouts, and review your training history on iPhone.

> **Status:** TestFlight only. The app is not yet on the App Store. Access is by request — open an issue or contact the maintainer for a TestFlight invite.

The companion Nuxt 4 / Postgres server is in a separate repository: **[DarthSaul/fitness-tracker](https://github.com/DarthSaul/fitness-tracker)**.

## Features

- **Sign in with Apple** authentication, with secure token storage in Keychain.
- **Program library** — browse and view fitness programs published by the platform.
- **Workouts** — start, run, and log live workouts with set-by-set tracking.
- **History** — review completed workouts and past activity.
- **Analytics** — visualize training trends over time.
- **Home** — daily overview and quick access to today's workout.
- **Settings & feedback** — manage account, sign out, and submit feedback.

## Screenshots

> _TODO: add screenshots of Home, Program detail, Live Workout, and History screens._

| Home | Program | Live Workout | History |
| :--: | :--: | :--: | :--: |
| _coming soon_ | _coming soon_ | _coming soon_ | _coming soon_ |

## Requirements

- macOS with **Xcode 15+**
- **iOS 17.6+** deployment target
- **Swift 5.0**
- A running instance of the [Fitness Tracker server](https://github.com/DarthSaul/fitness-tracker) reachable from the simulator or device
- Apple Developer account (required for Sign in with Apple capability and device builds)

## Getting started

1. **Clone the repo**

   ```sh
   git clone https://github.com/DarthSaul/fitness-tracker-mobile-app.git
   cd fitness-tracker-mobile-app
   ```

2. **Run the backend.** Clone and start [DarthSaul/fitness-tracker](https://github.com/DarthSaul/fitness-tracker) per its README. By default it serves on `http://localhost:3000`, which the iOS app's debug build is preconfigured to talk to.

3. **Open the Xcode project**

   ```sh
   open FitnessTracker/FitnessTracker.xcodeproj
   ```

4. **Build & run.** Select an iOS 17.6+ simulator (or a registered device) and press **⌘R**.

### Configuration

Build-time configuration lives in `FitnessTracker/FitnessTracker/Config/`:

- `Debug.xcconfig` — points `API_BASE_URL` at `http://localhost:3000`.
- `Release.xcconfig` — points at the production API host.

Both files also surface `SENTRY_DSN` into `Info.plist`. Sentry initialization is skipped when the DSN is left as the placeholder value, so local development works without a real DSN.

> **xcconfig gotcha:** xcconfig treats `//` as a comment regardless of context. URLs are assembled using a `SLASH = /` indirection (e.g. `http:$(SLASH)/host`) so two slashes never sit adjacent in the source. Don't use `\/\/` — backslashes pass through literally and end up percent-encoded.

## Architecture

- **UI:** SwiftUI with `@Observable` view models (modern Observation framework, not `ObservableObject`).
- **Persistence:** SwiftData (`@Model` types in `Core/Models/`).
- **Networking:** Custom `APIClient` + `APIEndpoint` enum in `Core/Networking/`. JSON is camelCase end-to-end.
- **Auth:** Sign in with Apple via `AuthenticationServices`. Access and refresh tokens are stored in Keychain. Token refresh is coalesced through an `actor`-based `TokenRefresher` to handle concurrent 401s safely.
- **Logging:** `OSLog` via category-scoped loggers in `Core/Logging/AppLogger.swift`.
- **Crash reporting:** Sentry, initialized in `FitnessTrackerApp.init()`.

Code is organized by feature under `FitnessTracker/FitnessTracker/Features/` (e.g. `Auth/`, `Programs/`, `Workouts/`, `History/`, `Analytics/`, `Settings/`), with cross-cutting concerns under `Core/`.

For deeper architectural details and conventions, see [`CLAUDE.md`](./CLAUDE.md).

## Project layout

```
FitnessTracker/
├── FitnessTracker.xcodeproj
├── FitnessTracker/
│   ├── FitnessTrackerApp.swift        # App entry point
│   ├── ContentView.swift
│   ├── Config/                         # Debug/Release xcconfig
│   ├── Core/                           # Networking, Auth, Models, Keychain, Logging, Persistence
│   └── Features/                       # Auth, Home, Programs, Workouts, History, Analytics, ...
├── FitnessTrackerTests/                # Unit tests (swift-testing)
└── FitnessTrackerUITests/              # UI tests
```

## Testing

Unit tests use Apple's [`swift-testing`](https://developer.apple.com/xcode/swift-testing/) framework (`@Test`, `#expect`) — not XCTest. Test helpers include `MockAPIClient` and `TestModelContainer` for isolating networking and persistence.

Run the suite from Xcode with **⌘U**.

## Contributing

Issues and pull requests are welcome. Before opening a PR:

- Follow the conventions described in [`CLAUDE.md`](./CLAUDE.md).
- Keep commit messages in the imperative mood, with no prefixes.
- Add or update tests for any behavior changes.

## License

Released under the [MIT License](./LICENSE).
