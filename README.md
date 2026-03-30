# LicenseManager

A Swift client SDK for managing license activation and validation in iOS and macOS apps.

## Why Use It

`LicenseManager` helps you ship paid license features faster without building your own entitlement state manager.

What it improves in your app flow:

- One shared licensing layer across iOS and macOS
- Instant `free/pro` state updates for SwiftUI
- Secure local persistence of activated licenses
- Built-in periodic validation strategy (with optional offline grace behavior)
- Clear user-facing error messages for failed activation attempts

## Requirements

- Swift 6
- macOS 13+
- iOS 15+

## Installation

### Xcode

1. Open your project.
2. Select `File > Add Package Dependencies...`
3. Enter:

```text
https://github.com/samuelail/licenseManager
```

4. Add the `LicenseManager` product to your app target.

### Package.swift

```swift
.package(url: "https://github.com/samuelail/licenseManager.git", from: "1.0.0")
```

Then add to your target dependencies:

```swift
.product(name: "LicenseManager", package: "licenseManager")
```

## Quick Start

```swift
import SwiftUI
import LicenseManager

@main
struct MyApp: App {
    @StateObject private var license = LicenseActivator(config: .init(
        appId: "YOUR_APP_ID",
        appSecret: "YOUR_APP_SECRET",
        baseURL: URL(string: "https://your-license-service.com")!,
        keychainService: "com.yourcompany.yourapp.license"
    ))

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(license)
                .task {
                    await license.validateIfNeeded()
                }
        }
    }
}
```

## Basic UI Usage

```swift
import SwiftUI
import LicenseManager

struct LicenseView: View {
    @EnvironmentObject var license: LicenseActivator
    @State private var code = ""

    var body: some View {
        VStack(spacing: 12) {
            if license.isProUser {
                Text("Pro is active")

                if let masked = license.maskedActivationCode {
                    Text(masked).foregroundStyle(.secondary)
                }

                Button("Deactivate") {
                    license.deactivate()
                }
            } else {
                TextField("License code", text: $code)
                    .textFieldStyle(.roundedBorder)

                Button("Activate") {
                    Task { await license.activate(code: code) }
                }

                if let error = license.activationError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .padding()
    }
}
```

## How It Behaves In-App

- On launch, call `validateIfNeeded()` to refresh entitlement state when required.
- When users activate, call `activate(code:)` and update UI from `license.plan` / `license.isProUser`.
- If users sign out or remove entitlement, call `deactivate()`.

The main state you’ll use:

- `plan` (`.free` or `.pro`)
- `isProUser` (convenience boolean)
- `activationError` (bind directly to UI)
- `maskedActivationCode` (safe display in settings screens)

## Configuration

`LicenseConfig` can be minimal:

```swift
let config = LicenseConfig(
    appId: "YOUR_APP_ID",
    appSecret: "YOUR_APP_SECRET"
)
```

Defaults:

- `baseURL`: `http://localhost:3000`
- `keychainService`: auto-generated from bundle id (fallback provided)
- `validationIntervalDays`: `7`
- `maxOfflineValidationDays`: `30`
- `keychainAccount`: `activation_code`

### Disable Scheduled Re-Validation

If you do not want automatic periodic checks:

```swift
let config = LicenseConfig(
    appId: "YOUR_APP_ID",
    appSecret: "YOUR_APP_SECRET",
    validationIntervalDays: nil,
    maxOfflineValidationDays: nil
)
```

## Typical Integration Pattern

1. Create a single `@StateObject` `LicenseActivator` at app root.
2. Inject it with `.environmentObject(license)`.
3. Gate premium features with `license.isProUser`.
4. Show `activationError` near your activation form.
5. Trigger `validateIfNeeded()` on launch.

## Best Practices

- Use a unique `keychainService` per app.
- Keep licensing UI in one settings/account screen.
- Always gate premium actions in code using `isProUser` (not just UI visibility).
- Treat activation as an async action and show progress/disabled button state.

## License

MIT
