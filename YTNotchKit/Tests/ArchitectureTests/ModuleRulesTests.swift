import Foundation
import Testing

/// The module rules from AGENTS.md, checked against the imports of every source file.
struct ModuleRulesTests {
    static let ownModules: Set<String> = ["PlayerCore", "WebPlayer", "NotchUI", "SystemMedia"]

    static let sourcesFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ArchitectureTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // YTNotchKit
        .appendingPathComponent("Sources")

    /// Matches `import X`, `@testable import X`, `public import X` and `import struct X.Y`.
    static var importLine: Regex<(Substring, Substring)> {
        /^\s*(?:@[\w]+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_]\w*)/
    }

    static func swiftFiles(in module: String) -> [URL] {
        let folder = sourcesFolder.appendingPathComponent(module)
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    static func imports(of module: String) throws -> Set<String> {
        var modules = Set<String>()
        for file in swiftFiles(in: module) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let match = line.firstMatch(of: importLine) {
                    modules.insert(String(match.1))
                }
            }
        }
        return modules
    }

    @Test(arguments: ["PlayerCore", "WebPlayer", "NotchUI", "SystemMedia"])
    func moduleHasSources(module: String) {
        #expect(!Self.swiftFiles(in: module).isEmpty, "No Swift files found for \(module), so its rules can't be checked")
    }

    @Test func playerCoreImportsOnlyFoundationAndObservation() throws {
        let extra = try Self.imports(of: "PlayerCore").subtracting(["Foundation", "Observation"])
        #expect(extra.isEmpty, "PlayerCore may import only Foundation and Observation, but imports \(extra.sorted())")
    }

    @Test(arguments: ["WebPlayer", "NotchUI", "SystemMedia"])
    func importsPlayerCoreAndNoOtherOwnModule(module: String) throws {
        let own = try Self.imports(of: module).intersection(Self.ownModules)
        #expect(own.contains("PlayerCore"), "\(module) must import PlayerCore")
        #expect(own == ["PlayerCore"], "\(module) must not import \(own.subtracting(["PlayerCore"]).sorted())")
    }

    /// The app makes no network requests of its own: the page loads everything, pictures
    /// included (YT-40). The update check (R5.2) lives in the app target, not here.
    @Test(arguments: ["PlayerCore", "WebPlayer", "NotchUI", "SystemMedia"])
    func noModuleMakesItsOwnNetworkRequests(module: String) throws {
        for file in Self.swiftFiles(in: module) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in ["URLSession", "NSURLConnection", "CFNetwork", "Data(contentsOf"] {
                #expect(!text.contains(name), "\(file.lastPathComponent) uses \(name)")
            }
        }
    }

    /// The app target too: its only network traffic will be the update check (R5.2), which
    /// the updater framework makes, not code here (I4.3).
    @Test func theAppTargetMakesNoNetworkRequestsOfItsOwn() throws {
        let app = Self.sourcesFolder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App")
        let files = (FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "No Swift files found in App")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in ["URLSession", "NSURLConnection", "CFNetwork", "Data(contentsOf"] {
                #expect(!text.contains(name), "\(file.lastPathComponent) uses \(name)")
            }
        }
    }

    @Test(arguments: ["PlayerCore", "NotchUI", "SystemMedia"])
    func onlyWebPlayerImportsWebKit(module: String) throws {
        #expect(!(try Self.imports(of: module).contains("WebKit")), "\(module) must not import WebKit")
    }
}
