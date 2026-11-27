# Swift-TestId-AutoInject

Auto-inject `accessibilityIdentifier` into SwiftUI views at build time: testID for native iOS.
Your source files do not change.

## Quick start

```bash
make install                 # builds and copies testid-inject to /usr/local/bin
cd path/to/YourApp
testid-inject setup          # edits YourApp.xcodeproj
```

Build the app in Debug. UI tests can now find the controls:

```swift
app.buttons["LoginView.button.sign-in"].tap()
```

Undo the setup with `testid-inject remove`.

## What `setup` changes

For every app target (or each `--target`):

1. Adds a `Generate Test IDs` Run Script phase before Compile Sources.
2. In Debug (or each `--configuration`), sets these build settings:

| Build setting | Value |
|---|---|
| `TESTID_INJECT` | `YES` |
| `OTHER_SWIFT_FLAGS` | adds `-vfsoverlay $(DERIVED_FILE_DIR)/testid/overlay.yaml` |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `NO` |

Running `setup` again changes nothing. Release builds contain no injected IDs.

If a teammate has not installed `testid-inject`, the build still passes with a warning.

## ID format

`<Type>.<control>.<label>`, built from the enclosing type and the first string literal:

| Source in `LoginView` | ID |
|---|---|
| `Button("Sign In") { }` | `LoginView.button.sign-in` |
| `TextField("Email", text: $email)` | `LoginView.textField.email` |
| `Button { } label: { Text("Help") }` | `LoginView.button` |
| A second `Button("OK")` | `LoginView.button.ok-2` |
| `Button("Keep") { }.accessibilityIdentifier("custom")` | `custom` (kept) |

Controls: `Button`, `TextField`, `SecureField`, `Toggle`, `NavigationLink`, `Picker`,
`Slider`, `Stepper`, `Link`, `Menu`. The build log lists every injected ID.

To see one file's result: `testid-inject rewrite path/to/View.swift`.

## How it works

1. The build phase runs `testid-inject generate`. It scans `$SRCROOT` and writes rewritten
   copies plus a VFS overlay to `$(DERIVED_FILE_DIR)/testid/`.
2. The compiler reads the copies through `-vfsoverlay` under the original paths, so
   diagnostics, `#filePath` and breakpoints point at your real files.
3. The modifier goes on the same line as the control, so line numbers do not shift.

## Settings

| Build setting | Effect |
|---|---|
| `TESTID_SOURCE_DIRS` | Folders to scan, separated by `:`. Default `$SRCROOT` |
| `TESTID_INJECTOR` | Path to `testid-inject` when it is not on `PATH` |

## Development

```bash
make test
TESTID_INJECTOR=$(swift build -c release --show-bin-path)/testid-inject scripts/verify.sh
```

`verify.sh` runs the Demo app: UI tests, a no-op rebuild, an incremental rebuild, a Release
build and a build without the tool. Keep `.build` and DerivedData outside iCloud-synced
folders; codesign rejects the extended attributes iCloud adds (use `--scratch-path`).

## Known limits

- Views inside SPM packages are not injected: package targets have no build phases.
- UIKit is not supported.
- A change to `testid-inject` alone does not trigger a recompile; clean the build.
- SwiftUI Previews and large-project build time are not measured yet.
