# Testing

- Automated tests and checks MUST run headlessly by default. They MUST NOT open, foreground, or leave GUI windows unless the user explicitly grants permission for windowed testing in that run.
- Prefer `flutter test` without a desktop device target for unit and widget tests. Commands such as `flutter test -d macos` can launch a native app window; use them only with explicit permission.
- User-visible app smoke tests that open a window also require explicit permission. Close windows opened for an approved test when finished.
