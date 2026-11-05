# Testing

Notation: requirements use [EARS+](design/README.md#requirement-notation-ears). IDs are `PNT-TST-<NNN>` and `PNT-VER-<NNN>`; each has a `Source:` line.

## Headless by Default

- **PNT-TST-001** The project shall run automated tests and checks headlessly by default.
  Source: project owner.
- **PNT-TST-002** The project shall not open, foreground, or leave GUI windows during an automated test or check, unless the user has explicitly granted permission for windowed testing in that run.
  Source: project owner.
- **PNT-TST-003** The project shall run unit and widget tests with `flutter test` without a desktop device target.
  Source: project owner.
- **PNT-TST-004** WHERE a command, such as `flutter test -d macos`, launches a native app window, the project shall use it only with explicit permission.
  Source: project owner.
- **PNT-TST-005** WHERE a user-visible app smoke test opens a window, the project shall require explicit permission before running it.
  Source: project owner.
- **PNT-TST-006** WHEN an approved windowed test finishes, the project shall close every window that the test opened.
  Source: project owner.

## Acceptance and Verification

- **PNT-VER-001** The project shall demonstrate each user-visible scenario in the behavioral documents under [`docs/design/`](design/README.md) on the finished macOS build; passing tests alone shall not satisfy this requirement.
  Source: T-001.
- **PNT-VER-002** The project shall cover applicable isolated behavior with unit tests.
  Source: T-001.
- **PNT-VER-003** The project shall cover interactions between modular components with integration tests, including drawing a stroke and verifying the resulting canvas and document change.
  Source: T-001.
