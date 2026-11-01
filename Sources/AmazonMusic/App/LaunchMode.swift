import Foundation

/// How this process was launched. `.normal` is the real app; the others render/check and exit without any web view.
enum LaunchMode: Equatable {
    case normal
    case snapshot(outDir: URL)
    case selftest

    static let current = parse(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)

    static func parse(arguments: [String], environment: [String: String] = [:]) -> LaunchMode {
        if arguments.contains("--selftest") { return .selftest }
        if let i = arguments.firstIndex(of: "--snapshot") {
            var dir = environment["APP_SNAPSHOT_DIR"] ?? "build/snapshots"
            if i + 1 < arguments.count, !arguments[i + 1].hasPrefix("-") { dir = arguments[i + 1] }
            return .snapshot(outDir: URL(fileURLWithPath: dir, isDirectory: true).standardizedFileURL)
        }
        return .normal
    }
}
