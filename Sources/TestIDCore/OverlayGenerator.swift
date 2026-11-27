import Foundation
import SwiftParser
import SwiftSyntax

public struct InjectedFile: Equatable, Sendable {
    public let source: String
    public let copy: String
    public let ids: [String]
}

public enum TestIDTransform {
    /// Returns the rewritten source and the injected IDs, or nil when nothing changed.
    public static func rewrite(source: String) -> (output: String, ids: [String])? {
        let rewriter = TestIDRewriter()
        let output = rewriter.rewrite(Parser.parse(source: source)).description
        return rewriter.injected.isEmpty ? nil : (output, rewriter.injected)
    }
}

/// Writes rewritten copies under `outDir` and a VFS overlay that maps each
/// original path to its copy. Files without controls stay out of the overlay.
public struct OverlayGenerator {
    public let outDir: URL
    public let overlay: URL

    public init(outDir: URL, overlay: URL) {
        self.outDir = outDir
        self.overlay = overlay
    }

    public func generate(sources: [String]) throws -> [InjectedFile] {
        let injected = try sources.compactMap(inject)
        try Self.writeOverlay(injected, to: overlay)
        return injected
    }

    public static func writeEmptyOverlay(to url: URL) throws {
        try writeOverlay([], to: url)
    }

    private func inject(_ path: String) throws -> InjectedFile? {
        let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
        let source = try String(contentsOfFile: absolute, encoding: .utf8)
        guard let result = TestIDTransform.rewrite(source: source) else { return nil }

        let copy = outDir.appendingPathComponent(absolute)
        try FileManager.default.createDirectory(
            at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.output.write(to: copy, atomically: true, encoding: .utf8)
        return InjectedFile(source: absolute, copy: copy.path, ids: result.ids)
    }

    private static func writeOverlay(_ files: [InjectedFile], to url: URL) throws {
        let roots = files.map { ["type": "file", "name": $0.source, "external-contents": $0.copy] }
        let json: [String: Any] = ["version": 0, "case-sensitive": "false", "roots": roots]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

/// Finds `.swift` files under the given roots, skipping build output and dependencies.
public enum SourceScanner {
    static let skippedDirectories: Set<String> = [
        "Pods", "Carthage", "DerivedData", "build", "Build", "node_modules", "SourcePackages",
    ]
    static let skippedExtensions: Set<String> = ["xcodeproj", "xcworkspace", "xcassets", "bundle"]

    public static func swiftFiles(in roots: [URL]) -> [String] {
        roots.flatMap(swiftFiles(in:)).sorted()
    }

    private static func swiftFiles(in root: URL) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [String] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skippedDirectories.contains(url.lastPathComponent)
                    || skippedExtensions.contains(url.pathExtension) {
                    enumerator.skipDescendants()
                }
            } else if url.pathExtension == "swift" {
                files.append(url.standardizedFileURL.path)
            }
        }
        return files
    }
}
