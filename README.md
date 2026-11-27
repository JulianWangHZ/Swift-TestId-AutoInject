# Swift-TestId-AutoInject

Auto-inject `accessibilityIdentifier` into SwiftUI views at build time: testID for native iOS.
Your source files do not change.

## Quick start

Install the CLI with one of:

```bash
brew install JulianWangHZ/tap/testid-inject
# or with Mint
mint install JulianWangHZ/Swift-TestId-AutoInject@v0.1.1
# or from a clone
git clone https://github.com/JulianWangHZ/Swift-TestId-AutoInject.git
cd Swift-TestId-AutoInject && make install   # PREFIX=~/.local to skip sudo
```

Then set up your app:

```bash
cd path/to/YourApp
testid-inject setup          # edits YourApp.xcodeproj
```

Build the app in Debug. UI tests can now find the controls:

```swift
app.buttons["login-sign-in-button"].tap()
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

`{screen}-{name}-{type}`, the same shape as the web injector, so Appium, XCUITest and
Playwright suites share one naming scheme.

- **screen**: the file name without `View` / `Screen` / `Page` / `ViewController`
  (`LoginView.swift` -> `login`).
- **name**: the first signal that yields a slug:
  1. ASCII label: `.accessibilityLabel("…")`, the title string, or the first `Text` / `Label`
     in the label closure.
  2. Handler intent: `action: submit`, `{ viewModel.signIn() }`, a binding such as
     `text: $email`, or `destination: SettingsView()`.
  3. Non-ASCII label, kept as is (`login-登入-button`).
  4. SF Symbol name (`Image(systemName: "trash")` -> `trash`).
  5. The control name.
- **type**: `button`, `input` (TextField, SecureField, TextEditor), `switch` (Toggle),
  `select` (Picker), `link`, `slider`, `stepper`, `menu`, `date-picker`.

| Source in `LoginView.swift` | ID |
|---|---|
| `Button("Sign In") { }` | `login-sign-in-button` |
| `TextField("Email", text: $email)` | `login-email-input` |
| `Button { } label: { Text("Help") }` | `login-help-button` |
| `Button(action: submit) { Image(systemName: "paperplane") }` | `login-submit-button` |
| `Button("登入") { }` | `login-登入-button` |
| A second `Button("OK")` in the same file | `login-ok-button-2` |
| `Button("Keep") { }.accessibilityIdentifier("custom")` | `custom` (kept) |

The build log lists every injected ID. To see one file's result:
`testid-inject rewrite path/to/View.swift`.

## Locating elements

```swift
// XCUITest
app.buttons["login-sign-in-button"].tap()
```

```python
# Appium (Python)
driver.find_element(AppiumBy.ACCESSIBILITY_ID, "login-sign-in-button").click()
```

### Rows share one id

A `ForEach` row is one call in source, so every row gets the same id. Pick a row at test time:

```swift
// XCUITest: by index
app.buttons.matching(identifier: "cart-remove-button").element(boundBy: 1).tap()
// XCUITest: by row content (List rows are cells)
app.cells.containing(.staticText, identifier: "Pear").buttons["cart-remove-button"].tap()
```

```python
# Appium: by index
driver.find_elements(AppiumBy.ACCESSIBILITY_ID, "cart-remove-button")[1].click()
# Appium: by row content
driver.find_element(AppiumBy.IOS_CLASS_CHAIN,
    '**/XCUIElementTypeCell[`label CONTAINS "Pear"`]/**/XCUIElementTypeButton[`name == "cart-remove-button"`]').click()
```

Or set a per-row id by hand; manual ids always win:
`.accessibilityIdentifier("cart-remove-\(item.id)")`.

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
