import ArgumentParser
import Foundation
import TestIDCore
import TestIDSetup

@main
struct TestIDInject: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "testid-inject",
        abstract: "Inject accessibilityIdentifier into SwiftUI controls at build time.",
        subcommands: [Setup.self, Remove.self, Generate.self, Rewrite.self]
    )
}

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add the build phase and Debug build settings to an .xcodeproj.")

    @Argument(help: "Path to the .xcodeproj. Defaults to the only one in the current folder.")
    var project: String?

    @Option(name: .long, help: "Target to set up. Repeat for more. Default: every app target.")
    var target: [String] = []

    @Option(name: .long, help: "Build configuration to inject in. Repeat for more.")
    var configuration: [String] = ["Debug"]

    func run() throws {
        let path = try ProjectLocator.resolve(project)
        let changed = try ProjectInstaller.install(
            projectAt: path, targets: target, configurations: configuration)
        print(changed.isEmpty
            ? "Already set up: \(path)"
            : "Set up \(changed.joined(separator: ", ")) in \(path) (\(configuration.joined(separator: ", ")))")
    }
}

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove the build phase and build settings added by setup.")

    @Argument(help: "Path to the .xcodeproj. Defaults to the only one in the current folder.")
    var project: String?

    @Option(name: .long, help: "Target to clean. Repeat for more. Default: every app target.")
    var target: [String] = []

    func run() throws {
        let path = try ProjectLocator.resolve(project)
        let changed = try ProjectInstaller.uninstall(projectAt: path, targets: target)
        print(changed.isEmpty ? "Nothing to remove: \(path)" : "Removed from \(changed.joined(separator: ", "))")
    }
}

struct Generate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write the overlay. Run by the Xcode build phase; reads Xcode's environment.")

    func run() throws {
        let env = ProcessInfo.processInfo.environment
        guard let derived = env["DERIVED_FILE_DIR"], let srcroot = env["SRCROOT"] else {
            throw ValidationError("DERIVED_FILE_DIR and SRCROOT are not set; run this from an Xcode build phase.")
        }
        let outDir = URL(fileURLWithPath: derived).appendingPathComponent("testid")
        let overlay = outDir.appendingPathComponent("overlay.yaml")
        let roots = (env["TESTID_SOURCE_DIRS"].flatMap { $0.isEmpty ? nil : $0 } ?? srcroot)
            .split(separator: ":").map { URL(fileURLWithPath: String($0)) }

        do {
            try? FileManager.default.removeItem(at: outDir)
            let generator = OverlayGenerator(outDir: outDir.appendingPathComponent("src"), overlay: overlay)
            let files = try generator.generate(sources: SourceScanner.swiftFiles(in: roots))
            let count = files.reduce(0) { $0 + $1.ids.count }
            print("testid-inject: \(count) IDs in \(files.count) files")
            for file in files {
                print("  \(file.source): \(file.ids.joined(separator: ", "))")
            }
        } catch {
            // A failed injection must not fail the app build.
            print("warning: testid-inject failed (\(error)); building without test IDs")
            try OverlayGenerator.writeEmptyOverlay(to: overlay)
        }
    }
}

struct Rewrite: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print a file with test IDs injected, for checking the result.")

    @Argument(help: "Swift source file.")
    var file: String

    func run() throws {
        let source = try String(contentsOfFile: file, encoding: .utf8)
        print(TestIDTransform.rewrite(source: source, fileName: file)?.output ?? source, terminator: "")
    }
}

enum ProjectLocator {
    static func resolve(_ path: String?) throws -> String {
        if let path { return path }
        let cwd = FileManager.default.currentDirectoryPath
        let projects = try FileManager.default.contentsOfDirectory(atPath: cwd)
            .filter { $0.hasSuffix(".xcodeproj") }
        guard projects.count == 1 else {
            throw ValidationError(projects.isEmpty
                ? "No .xcodeproj in \(cwd). Pass the path."
                : "Several .xcodeproj in \(cwd): \(projects.joined(separator: ", ")). Pass one.")
        }
        return (cwd as NSString).appendingPathComponent(projects[0])
    }
}
