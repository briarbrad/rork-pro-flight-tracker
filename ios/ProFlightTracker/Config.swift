import Foundation

/// Rork injects `EXPO_PUBLIC_BACKEND_API_TOKEN` into this type at preview/build
/// time. The committed stub is empty on purpose:
///
/// - Empty is valid while Railway `REQUIRE_AUTH` is off (current default).
/// - When you flip `REQUIRE_AUTH=1`, set the Rork secret
///   `EXPO_PUBLIC_BACKEND_API_TOKEN` to the same value as Railway `API_TOKEN`.
/// - Never put AeroAPI or OpenRouter keys here. Those stay server-side.
///
/// This file is gitignored so a locally injected secret is not committed
/// by `git add .`. The stub is force-tracked so Xcode/Rork clones still compile.
enum Config {
    static let EXPO_PUBLIC_BACKEND_API_TOKEN = ""
}
