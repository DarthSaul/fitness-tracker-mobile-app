# Release cycle

How a change gets from `main` to users' phones. Three Fastlane lanes cover the whole cycle; everything else happens in App Store Connect.

| Lane | Run it when | What it does |
| --- | --- | --- |
| `bundle exec fastlane bump type:patch\|minor\|major` | Once, at the start of a release train | Bumps the marketing version (X.Y.Z) and commits |
| `bundle exec fastlane beta` | As often as you like | Builds, uploads to TestFlight, distributes to the external group, commits the build-number bump |
| `bundle exec fastlane release` | When the latest TestFlight build is the one to ship | Submits that build for App Store review with phased release on, tags the commit |

All lanes commit and tag **locally only**. Push when you are happy with the result.

## Prerequisites

- **Ruby + Bundler.** Fastlane is pinned in the root `Gemfile` and installs into `vendor/bundle` (see `.bundle/config`). Run `bundle install` once.
- **`fastlane/.env` populated.** Copy `fastlane/.env.example` and fill in `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_FILEPATH`. The file is gitignored.
- **The `.p8` key** at the path named by `ASC_KEY_FILEPATH`, normally `~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8`. Generate it at [App Store Connect → Integrations → API keys](https://appstoreconnect.apple.com/access/integrations/api) with the App Manager role. Apple only offers the download once.
- **Xcode signed in** to the Apple Developer account (Xcode → Settings → Accounts) so automatic signing can fetch the App Store distribution profile at archive time.
- **A clean working tree.** `bump`, `beta`, and `release` each commit or tag, so every lane refuses to start if `git status` shows changes. Stash unrelated edits first.

## Release flow

### 1. Bump the marketing version

```sh
bundle exec fastlane bump type:minor   # or type:patch / type:major (default: patch)
```

Run this **once** at the start of a release train. It rewrites `MARKETING_VERSION` in the Xcode project and commits `Bump version to X.Y.Z`.

Two numbers identify a build:

- **Marketing version** (`MARKETING_VERSION`, e.g. `1.1.0`) is what users see on the App Store. `bump` only changes it in the Xcode project; App Store Connect creates the matching version when the first build carrying it is uploaded by `beta`, and `release` fills it in. Only `bump` changes it.
- **Build number** (`CURRENT_PROJECT_VERSION`, e.g. `17`) only has to be unique within a marketing version. `beta` bumps it automatically on every upload, so you never edit it by hand.

Use `patch` for fixes to the live version, `minor` for new features, `major` for breaking redesigns.

### 2. Write the release notes

Edit `fastlane/metadata/en-US/release_notes.txt`. This text is used twice: as the TestFlight "What to Test" for every beta build of this version, and as the App Store "What's New" when you run `release`. Commit it with the version bump or on its own.

You can override the TestFlight text for a single build with `bundle exec fastlane beta changelog:"Try the new timer"`.

### 3. Ship TestFlight builds

```sh
bundle exec fastlane beta
```

Repeat as often as needed. Each run asks TestFlight for the highest build number, adds one, archives the Release configuration, uploads, commits `Bump build to N for TestFlight`, and tags that commit `build-N`. The tag records exactly which source went into build N; `release` uses it later.

What to expect:

- **The lane blocks while Apple processes the build,** typically 5 to 30 minutes. This is required, because a build can only be assigned to an external group after processing. The lane gives up after 30 minutes; see Troubleshooting.
- **The external group receives every build.** The group name is the `EXTERNAL_GROUPS` constant in `fastlane/Fastfile` (`Friends` today) and must match App Store Connect exactly.
- **Every build is submitted for Beta App Review,** and external testers only receive a build after Apple approves it. The first build of a new marketing version gets a full review, which usually takes about a day. Later builds of the same marketing version are normally approved within minutes, but that is Apple's call, not a guarantee. Whether testers are notified also depends on the group's "Automatically notify testers" setting in App Store Connect; with it off, notify them by hand.

### 4. Deploy server changes first

If the release depends on API changes, deploy them from the `fitness-tracker` server repo **before** submitting the app. Reviewers test against production, and users on the previous binary keep hitting the API for weeks after release, so every API change must stay backward-compatible with the version currently on the App Store.

### 5. Submit for review

```sh
bundle exec fastlane release
```

This does **not** rebuild. It reads the marketing version from the project, finds the latest TestFlight build with that version, creates or updates the App Store version in App Store Connect, uploads the release notes, attaches the build, and submits it for review with **phased release** enabled and **automatic release** off. It then tags the commit that build N was archived from (found via its `build-N` tag) as `vX.Y.Z-N`, even if your HEAD has moved on since. The `build-N` tag is checked **before** anything is submitted; if it is missing locally the lane stops there, with nothing sent to Apple, rather than tagging unrelated source; see Troubleshooting.

Before uploading metadata, Fastlane renders an HTML preview and asks you to confirm. Once you trust the flow, set `force: true` on `upload_to_app_store` in the Fastfile to skip that prompt.

Status in App Store Connect after the lane finishes:

- **Waiting for Review** → the submission is queued. Review usually takes one to two days.
- **In Review** → a reviewer has it.
- **Pending Developer Release** → approved, but not yet live because automatic release is off. Nothing happens until you press the button in step 6.
- **Ready for Distribution** → Apple has approved it and you have pressed **Release This Version** (step 6). Approval alone does not make the version available: with automatic release off it stays in Pending Developer Release until you release it, and once released the phased rollout controls who actually gets it.
- **Rejected** → read the Resolution Center message, fix, run `beta` again, then `release` again. The live version is unaffected.

### 6. Release it

In App Store Connect open the version and press **Release This Version**.

Because phased release is on, the update rolls out to users who have automatic updates enabled over **7 days**, roughly 1%, 2%, 5%, 10%, 20%, 50%, then 100%. Anyone can install it immediately from the App Store page; phasing only affects automatic updates. While the rollout is in progress you can:

- **Pause** it if crash reports or Sentry spike. The seven-day clock stops while paused, but Apple caps the total time paused, across all pauses, at 30 days.
- **Resume** it once a fix is verified, or
- **Release to all users** to skip the remaining phases.

Pause when Sentry shows a new crash or error that affects a meaningful share of sessions on the new version. A paused rollout cannot be rolled back, so the fix is a hotfix (below).

### 7. Push

```sh
git push && git push --tags
```

`bump`, `beta`, and `release` all committed or tagged locally. Push so `main`, the `build-N` tags, and the release tag `vX.Y.Z-N` reflect what shipped.

## Hotfix

Same flow with `type:patch`:

```sh
bundle exec fastlane bump type:patch
# edit fastlane/metadata/en-US/release_notes.txt
bundle exec fastlane beta
bundle exec fastlane release
```

A new marketing version means the first beta build goes through Beta App Review again. If the fix is urgent and you are confident, you can run `release` as soon as `beta` finishes without waiting for testers; the App Store submission does not depend on Beta App Review. You may also want to release to all users at step 6 rather than phasing.

Nothing you submit affects the live version until it is approved **and** released. A rejected update never touches what users have.

## TestFlight vs App Store on the same device

TestFlight builds and the App Store build share the bundle ID `me.fitness-app.tracker`, so a device holds only one copy of the app at a time:

- Installing from TestFlight replaces the App Store copy, and installing from the App Store replaces the TestFlight copy. **The most recent install wins,** regardless of version number.
- App data (Keychain tokens, SwiftData store, settings) persists across those swaps. Testers do not need to sign in again.
- **TestFlight builds expire 90 days after upload.** After that the app refuses to launch until the tester installs a newer build or the App Store version.
- When testing is over, testers should reinstall from the App Store so they get automatic updates. The App Store will not offer an update to a device running a TestFlight build with a higher build number.

## Troubleshooting

**`beta` hangs or times out at "Waiting for processing".** Apple's processing occasionally takes longer than the 30-minute cap, and the lane exits with an error even though the upload succeeded. Check TestFlight in App Store Connect. If the build is there, add it to the external group by hand. Do not re-run `beta`; it would upload a duplicate build. The build-number commit was not made, so run `git status` and commit the `project.pbxproj` change yourself.

**`No TestFlight build found for version X.Y.Z`.** `release` only looks at builds whose marketing version matches the project. Either `beta` has not run since the last `bump`, the build is still processing, or the `bump` commit is not on your current branch. Run `beta` (or wait), then retry.

**`release` fails with `No local tag build-N`.** Nothing was submitted; the lane checks for the tag before contacting Apple. The build was uploaded from another checkout, or its `build-N` tag was never pushed. Run `git fetch --tags`; if the tag does not exist anywhere, find the commit the build was archived from (the `Bump build to N for TestFlight` commit) and create it by hand with `git tag build-N <sha>`. Then re-run `release`.

**A lane refuses to start with `Git repository is dirty`.** Every lane checks for a clean tree before doing anything. Commit or stash your changes and re-run.

**`beta` fails after processing with a group error.** The name in `EXTERNAL_GROUPS` (`fastlane/Fastfile`) does not match App Store Connect → TestFlight → External Testing. Group names are case-sensitive. Fix the constant, then add the already-uploaded build to the group manually; do not re-run `beta`.

**`release` fails in precheck.** Precheck scans metadata for things Apple rejects (placeholder text, "beta", competitor names). Fix the release notes and retry. Precheck cannot inspect in-app purchases with API-key authentication, which is why that check is disabled in the Fastfile.

**Authentication errors.** Confirm `fastlane/.env` is present and that `ASC_KEY_FILEPATH` points at an existing `.p8`. The key needs the App Manager role to submit for review.
