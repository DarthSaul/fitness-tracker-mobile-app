# FitnessTracker – Claude Code Guide

## Project Overview

iOS-native fitness tracking app built with SwiftUI, SwiftData, and Sentry. The app uses Sign in with Apple for authentication, communicates with a REST API, and caches data locally with SwiftData.

- **Bundle ID:** `me.fitness-app.fitness`
- **Minimum Deployment Target:** iOS 17.6
- **Swift Version:** 5.0
- **Xcode Project:** `FitnessTracker/FitnessTracker.xcodeproj`

## Build Commands

```bash
# Build for simulator
xcodebuild -project FitnessTracker/FitnessTracker.xcodeproj \
  -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Build and test (unit tests)
xcodebuild -project FitnessTracker/FitnessTracker.xcodeproj \
  -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

No separate lint step is configured; the project uses the Swift compiler's built-in warnings.

## Architecture

The codebase follows an MVVM pattern with a layered networking and persistence stack.

```
FitnessTracker/
├── FitnessTracker/
│   ├── FitnessTrackerApp.swift      # App entry point, DI root
│   ├── ContentView.swift
│   ├── Core/
│   │   ├── Auth/                    # SessionManager, TokenStore, TokenRefresher
│   │   ├── Config/                  # APIConfig (reads from xcconfig / Info.plist)
│   │   ├── Keychain/                # KeychainService, KeychainKey
│   │   ├── Logging/                 # AppLogger (OSLog subsystem extensions)
│   │   ├── Models/                  # SwiftData model definitions
│   │   ├── Networking/              # APIClient, APIEndpoint, APIError, TokenRefresher, JSONCoding
│   │   └── Persistence/             # PersistenceContainer (SwiftData ModelContainer)
│   └── Features/
│       ├── Auth/                    # AuthView, AuthViewModel, AuthRepository
│       └── Programs/                # ProgramListView, ProgramListViewModel, ProgramRepository
├── FitnessTrackerTests/             # Unit tests (Swift Testing framework)
│   ├── Features/Programs/
│   └── Helpers/                     # MockAPIClient, TestModelContainer
└── FitnessTrackerUITests/           # XCTest UI tests
```

### Key Patterns

- **Dependency injection** via SwiftUI `.environment()` — `SessionManager` and `APIClient` are `@Observable` and injected at the scene level.
- **Networking** — `APIClient` is the single HTTP layer. It handles JWT bearer auth, automatic 401 token refresh (via `TokenRefresher`), and typed errors (`APIError`).
- **Token lifecycle** — Access token lives in `TokenStore` (an actor); refresh token is persisted to Keychain. On 401, the client retries exactly once after refreshing.
- **Persistence** — SwiftData (`ModelContext`) for local caching. `ProgramRepository` upserts API DTOs into SwiftData models.
- **Configuration** — API base URL and Sentry DSN are injected through `.xcconfig` files into `Info.plist`; never hard-coded.
- **Logging** — Use `Logger.networking`, `Logger.auth`, `Logger.data`, etc. (defined in `AppLogger.swift`). Mark sensitive data with `privacy: .private`.

## Git Command Conventions

* Never prefix git commands with `cd`
