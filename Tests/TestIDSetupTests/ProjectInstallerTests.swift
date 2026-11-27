import Foundation
import PathKit
@testable import TestIDSetup
import XcodeProj
import XCTest

final class ProjectInstallerTests: XCTestCase {
    private var projectPath: String!

    override func setUpWithError() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/Demo", withExtension: "xcodeproj"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.copyItem(at: fixture, to: copy)
        projectPath = copy.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: (projectPath as NSString).deletingLastPathComponent)
    }

    // XcodeProj objects reference each other weakly; keep the loaded project alive.
    private var loaded: XcodeProj?

    private func target(_ name: String = "Demo") throws -> PBXNativeTarget {
        let project = try XcodeProj(path: Path(projectPath))
        loaded = project
        return try XCTUnwrap(project.pbxproj.nativeTargets.first { $0.name == name })
    }

    private func settings(_ config: String, target name: String = "Demo") throws -> BuildSettings {
        let configs = try target(name).buildConfigurationList?.buildConfigurations ?? []
        return try XCTUnwrap(configs.first { $0.name == config }).buildSettings
    }

    private func pbxprojText() throws -> String {
        try String(contentsOfFile: projectPath + "/project.pbxproj", encoding: .utf8)
    }

    func testInstallLeavesSharedSchemesUntouched() throws {
        let schemes = projectPath + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(atPath: schemes, withIntermediateDirectories: true)
        let scheme = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme
           LastUpgradeVersion = "1430"
           version = "2.0"
           wasCreatedForAppExtension = "YES">
        </Scheme>

        """
        try scheme.write(toFile: schemes + "/Demo.xcscheme", atomically: true, encoding: .utf8)

        try ProjectInstaller.install(projectAt: projectPath)
        try ProjectInstaller.uninstall(projectAt: projectPath)

        XCTAssertEqual(try String(contentsOfFile: schemes + "/Demo.xcscheme", encoding: .utf8), scheme)
    }

    func testInstallAddsPhaseBeforeSources() throws {
        XCTAssertEqual(try ProjectInstaller.install(projectAt: projectPath), ["Demo"])

        let phases = try target().buildPhases
        let scriptIndex = try XCTUnwrap(phases.firstIndex { $0.name() == ProjectInstaller.phaseName })
        let sourcesIndex = try XCTUnwrap(phases.firstIndex { $0.buildPhase == .sources })
        XCTAssertLessThan(scriptIndex, sourcesIndex)
    }

    func testInstallSetsDebugOnly() throws {
        try ProjectInstaller.install(projectAt: projectPath)

        let debug = try settings("Debug")
        XCTAssertEqual(debug["TESTID_INJECT"], .string("YES"))
        XCTAssertEqual(debug["ENABLE_USER_SCRIPT_SANDBOXING"], .string("NO"))
        XCTAssertEqual(debug["OTHER_SWIFT_FLAGS"],
                       .string("$(inherited) -vfsoverlay $(DERIVED_FILE_DIR)/testid/overlay.yaml"))

        let release = try settings("Release")
        XCTAssertNil(release["TESTID_INJECT"])
        XCTAssertNil(release["OTHER_SWIFT_FLAGS"])
    }

    func testInstallSkipsNonAppTargets() throws {
        try ProjectInstaller.install(projectAt: projectPath)
        XCTAssertFalse(try target("DemoUITests").buildPhases.contains { $0.name() == ProjectInstaller.phaseName })
        XCTAssertNil(try settings("Debug", target: "DemoUITests")["TESTID_INJECT"])
    }

    func testInstallIsIdempotent() throws {
        try ProjectInstaller.install(projectAt: projectPath)
        let once = try pbxprojText()
        XCTAssertEqual(try ProjectInstaller.install(projectAt: projectPath), [])
        XCTAssertEqual(try pbxprojText(), once)
    }

    func testRemoveUndoesInstall() throws {
        try ProjectInstaller.install(projectAt: projectPath)
        XCTAssertEqual(try ProjectInstaller.uninstall(projectAt: projectPath), ["Demo"])

        XCTAssertFalse(try pbxprojText().contains(ProjectInstaller.phaseName))
        let debug = try settings("Debug")
        XCTAssertNil(debug["TESTID_INJECT"])
        XCTAssertNil(debug["OTHER_SWIFT_FLAGS"])
        XCTAssertEqual(try ProjectInstaller.uninstall(projectAt: projectPath), [])
    }

    func testRemoveRestoresSandboxingWhenItWasUnset() throws {
        XCTAssertNil(try settings("Debug")["ENABLE_USER_SCRIPT_SANDBOXING"])
        let before = try settings("Debug")

        try ProjectInstaller.install(projectAt: projectPath)
        try ProjectInstaller.uninstall(projectAt: projectPath)

        XCTAssertEqual(try settings("Debug"), before)
    }

    func testRemoveRestoresSandboxingWhenItWasYes() throws {
        let project = try XcodeProj(path: Path(projectPath))
        let target = try XCTUnwrap(project.pbxproj.nativeTargets.first { $0.name == "Demo" })
        let debug = try XCTUnwrap(target.buildConfigurationList?.buildConfigurations.first { $0.name == "Debug" })
        debug.buildSettings["ENABLE_USER_SCRIPT_SANDBOXING"] = .string("YES")
        try project.pbxproj.write(path: XcodeProj.pbxprojPath(Path(projectPath)), override: true)
        let before = try settings("Debug")

        try ProjectInstaller.install(projectAt: projectPath)
        XCTAssertEqual(try settings("Debug")["ENABLE_USER_SCRIPT_SANDBOXING"], .string("NO"))
        try ProjectInstaller.install(projectAt: projectPath)
        try ProjectInstaller.uninstall(projectAt: projectPath)

        XCTAssertEqual(try settings("Debug"), before)
    }

    func testUnknownTargetLists() {
        XCTAssertThrowsError(try ProjectInstaller.install(projectAt: projectPath, targets: ["Nope"])) { error in
            XCTAssertEqual(error as? SetupError, .unknownTargets(["Nope"], available: ["Demo", "DemoUITests"]))
        }
    }

    func testUnknownConfigurationLists() {
        XCTAssertThrowsError(try ProjectInstaller.install(projectAt: projectPath, configurations: ["Staging"])) { error in
            XCTAssertEqual(error as? SetupError, .unknownConfigurations(["Staging"], available: ["Debug", "Release"]))
        }
    }
}

final class OverlayFlagTests: XCTestCase {
    func testAppendsToExistingString() {
        XCTAssertEqual(ProjectInstaller.addingOverlayFlag(to: .string("$(inherited) -DFOO")),
                       .string("$(inherited) -DFOO -vfsoverlay $(DERIVED_FILE_DIR)/testid/overlay.yaml"))
    }

    func testAppendsToArray() {
        XCTAssertEqual(ProjectInstaller.addingOverlayFlag(to: .array(["-DFOO"])),
                       .array(["-DFOO", "-vfsoverlay", "$(DERIVED_FILE_DIR)/testid/overlay.yaml"]))
    }

    func testRemoveKeepsOtherFlags() {
        let installed = ProjectInstaller.addingOverlayFlag(to: .string("$(inherited) -DFOO"))
        XCTAssertEqual(ProjectInstaller.removingOverlayFlag(from: installed), .string("$(inherited) -DFOO"))
        let array = ProjectInstaller.addingOverlayFlag(to: .array(["-DFOO"]))
        XCTAssertEqual(ProjectInstaller.removingOverlayFlag(from: array), .array(["-DFOO"]))
    }
}
