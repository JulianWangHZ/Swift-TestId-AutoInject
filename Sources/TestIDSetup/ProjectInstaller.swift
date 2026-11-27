import Foundation
import PathKit
import XcodeProj

public enum SetupError: Error, CustomStringConvertible, Equatable {
    case noAppTargets
    case unknownTargets([String], available: [String])
    case unknownConfigurations([String], available: [String])

    public var description: String {
        switch self {
        case .noAppTargets:
            "No application target found. Pass --target <name>."
        case let .unknownTargets(names, available):
            "Unknown target(s): \(names.joined(separator: ", ")). Available: \(available.joined(separator: ", "))"
        case let .unknownConfigurations(names, available):
            "Unknown configuration(s): \(names.joined(separator: ", ")). Available: \(available.joined(separator: ", "))"
        }
    }
}

/// Adds or removes the test ID build phase and build settings in an `.xcodeproj`.
public enum ProjectInstaller {
    public static let phaseName = "Generate Test IDs"
    static let overlayPath = "$(DERIVED_FILE_DIR)/testid/overlay.yaml"
    static let overlayFlag = "-vfsoverlay \(overlayPath)"
    static let marker = "testid/overlay.yaml"

    static let shellScript = """
    # Managed by `testid-inject setup`. Remove with `testid-inject remove`.
    if [ "${TESTID_INJECT:-NO}" != "YES" ]; then exit 0; fi
    export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.mint/bin:$HOME/.local/bin"
    TOOL="${TESTID_INJECTOR:-$(command -v testid-inject || true)}"
    if [ -n "$TOOL" ] && [ -x "$TOOL" ]; then
      exec "$TOOL" generate
    fi
    echo "warning: testid-inject is not installed; building without test IDs"
    mkdir -p "$DERIVED_FILE_DIR/testid"
    printf '{"version":0,"roots":[]}' > "$DERIVED_FILE_DIR/testid/overlay.yaml"

    """

    /// Returns the names of the targets that changed.
    @discardableResult
    public static func install(
        projectAt path: String, targets names: [String]? = nil, configurations: [String] = ["Debug"]
    ) throws -> [String] {
        try edit(projectAt: path, targets: names) { pbxproj, target in
            let configs = try matchingConfigurations(of: target, names: configurations)
            var changed = addPhase(to: target, in: pbxproj)
            for config in configs {
                changed = applyInstall(to: config) || changed
            }
            return changed
        }
    }

    /// Returns the names of the targets that changed.
    @discardableResult
    public static func uninstall(projectAt path: String, targets names: [String]? = nil) throws -> [String] {
        try edit(projectAt: path, targets: names) { pbxproj, target in
            var changed = removePhase(from: target, in: pbxproj)
            for config in target.buildConfigurationList?.buildConfigurations ?? [] {
                changed = applyUninstall(to: config) || changed
            }
            return changed
        }
    }

    // MARK: - Project editing

    private static func edit(
        projectAt path: String,
        targets names: [String]?,
        _ body: (PBXProj, PBXNativeTarget) throws -> Bool
    ) throws -> [String] {
        let projectPath = Path(path)
        let project = try XcodeProj(path: projectPath)
        let targets = try selectTargets(in: project.pbxproj, names: names)
        var changed: [String] = []
        for target in targets where try body(project.pbxproj, target) {
            changed.append(target.name)
        }
        if !changed.isEmpty {
            // Write only the pbxproj: `XcodeProj.write` also re-serializes shared schemes.
            try project.pbxproj.write(path: XcodeProj.pbxprojPath(projectPath), override: true)
        }
        return changed
    }

    static func selectTargets(in pbxproj: PBXProj, names: [String]?) throws -> [PBXNativeTarget] {
        let all = pbxproj.nativeTargets.sorted { $0.name < $1.name }
        guard let names, !names.isEmpty else {
            let apps = all.filter { $0.productType == .application }
            guard !apps.isEmpty else { throw SetupError.noAppTargets }
            return apps
        }
        let missing = names.filter { name in !all.contains { $0.name == name } }
        guard missing.isEmpty else {
            throw SetupError.unknownTargets(missing, available: all.map(\.name))
        }
        return all.filter { names.contains($0.name) }
    }

    private static func matchingConfigurations(
        of target: PBXNativeTarget, names: [String]
    ) throws -> [XCBuildConfiguration] {
        let all = target.buildConfigurationList?.buildConfigurations ?? []
        let missing = names.filter { name in !all.contains { $0.name == name } }
        guard missing.isEmpty else {
            throw SetupError.unknownConfigurations(missing, available: all.map(\.name))
        }
        return all.filter { names.contains($0.name) }
    }

    // MARK: - Build phase

    private static func existingPhase(in target: PBXNativeTarget) -> PBXShellScriptBuildPhase? {
        target.buildPhases
            .compactMap { $0 as? PBXShellScriptBuildPhase }
            .first { $0.name == phaseName }
    }

    private static func addPhase(to target: PBXNativeTarget, in pbxproj: PBXProj) -> Bool {
        if let phase = existingPhase(in: target) {
            guard phase.shellScript != shellScript else { return false }
            phase.shellScript = shellScript
            return true
        }
        let phase = PBXShellScriptBuildPhase(
            name: phaseName,
            shellPath: "/bin/sh",
            shellScript: shellScript,
            showEnvVarsInLog: false,
            alwaysOutOfDate: true
        )
        pbxproj.add(object: phase)
        let index = target.buildPhases.firstIndex { $0.buildPhase == .sources } ?? 0
        target.buildPhases.insert(phase, at: index)
        return true
    }

    private static func removePhase(from target: PBXNativeTarget, in pbxproj: PBXProj) -> Bool {
        guard let phase = existingPhase(in: target) else { return false }
        target.buildPhases.removeAll { $0 === phase }
        pbxproj.delete(object: phase)
        return true
    }

    // MARK: - Build settings

    private static let sandboxing = "ENABLE_USER_SCRIPT_SANDBOXING"
    private static let sandboxingBefore = "TESTID_INJECT_SANDBOXING_BEFORE"
    private static let unsetMarker = "unset"

    private static func applyInstall(to config: XCBuildConfiguration) -> Bool {
        let before = config.buildSettings
        var settings = before
        settings["TESTID_INJECT"] = .string("YES")
        if settings[sandboxing] != .string("NO") {
            // Remember the old value so `remove` can put it back.
            settings[sandboxingBefore] = settings[sandboxing] ?? .string(unsetMarker)
            settings[sandboxing] = .string("NO")
        }
        settings["OTHER_SWIFT_FLAGS"] = addingOverlayFlag(to: settings["OTHER_SWIFT_FLAGS"])
        config.buildSettings = settings
        return settings != before
    }

    private static func applyUninstall(to config: XCBuildConfiguration) -> Bool {
        let before = config.buildSettings
        guard before["TESTID_INJECT"] != nil || hasOverlayFlag(before["OTHER_SWIFT_FLAGS"]) else {
            return false
        }
        var settings = before
        settings["TESTID_INJECT"] = nil
        // Installs made before the saved value existed leave sandboxing as is.
        if let saved = settings[sandboxingBefore] {
            settings[sandboxing] = saved == .string(unsetMarker) ? nil : saved
            settings[sandboxingBefore] = nil
        }
        settings["OTHER_SWIFT_FLAGS"] = removingOverlayFlag(from: settings["OTHER_SWIFT_FLAGS"])
        config.buildSettings = settings
        return settings != before
    }

    static func hasOverlayFlag(_ setting: BuildSetting?) -> Bool {
        switch setting {
        case let .string(value): value.contains(marker)
        case let .array(values): values.contains { $0.contains(marker) }
        case nil: false
        }
    }

    static func addingOverlayFlag(to setting: BuildSetting?) -> BuildSetting {
        guard !hasOverlayFlag(setting) else { return setting! }
        switch setting {
        case let .string(value): return .string("\(value) \(overlayFlag)")
        case let .array(values): return .array(values + ["-vfsoverlay", overlayPath])
        case nil: return .string("$(inherited) \(overlayFlag)")
        }
    }

    static func removingOverlayFlag(from setting: BuildSetting?) -> BuildSetting? {
        switch setting {
        case let .string(value):
            let rest = value.replacingOccurrences(of: overlayFlag, with: "")
                .split(separator: " ").joined(separator: " ")
            return rest.isEmpty || rest == "$(inherited)" ? nil : .string(rest)
        case let .array(values):
            var rest: [String] = []
            var index = values.startIndex
            while index < values.endIndex {
                if values[index] == "-vfsoverlay", index + 1 < values.endIndex,
                   values[index + 1].contains(marker) {
                    index += 2
                    continue
                }
                rest.append(values[index])
                index += 1
            }
            return rest.isEmpty || rest == ["$(inherited)"] ? nil : .array(rest)
        case nil:
            return nil
        }
    }
}
