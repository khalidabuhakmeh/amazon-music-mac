import Foundation

/// Runs the CLI when a command follows the binary's name, else the app.
/// Launch flags (`--snapshot`, `--selftest`, `-NS*`, `-Apple*`, `-XCTest*`, ...) all start with "-"
/// and never reach the CLI; only `--help`, `-h` and `--version` do. The CLI client never starts the UI.
@main
enum Main {
    @MainActor
    static func main() {
        if let code = AgentCLI.runIfRequested() { exit(code) }
        AmazonMusicApp.main()
    }
}
