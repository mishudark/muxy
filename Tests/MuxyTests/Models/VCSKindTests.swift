import Foundation
import Testing

@testable import Muxy

@Suite("VCSKind")
struct VCSKindTests {
    private let fm = FileManager.default

    private func makeTempDir() throws -> String {
        let base = NSTemporaryDirectory()
        let name = UUID().uuidString
        let path = (base as NSString).appendingPathComponent(name)
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanup(_ path: String) {
        try? fm.removeItem(atPath: path)
    }

    private func createDir(_ path: String) throws {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func createFile(_ path: String) throws {
        fm.createFile(atPath: path, contents: Data(), attributes: nil)
    }

    @Test("detects native jj repo at root")
    func nativeJJAtRoot() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createDir((root as NSString).appendingPathComponent(".jj"))

        let result = await VCSKind.detect(at: root)
        #expect(result == .jjNative)
    }

    @Test("detects colocated jj repo at root")
    func colocatedJJAtRoot() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createDir((root as NSString).appendingPathComponent(".jj"))
        try createDir((root as NSString).appendingPathComponent(".git"))

        let result = await VCSKind.detect(at: root)
        #expect(result == .jjColocated)
    }

    @Test("detects git repo at root")
    func gitAtRoot() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createDir((root as NSString).appendingPathComponent(".git"))

        let result = await VCSKind.detect(at: root)
        #expect(result == .git)
    }

    @Test("returns nil for plain directory")
    func noRepo() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }

        let result = await VCSKind.detect(at: root)
        #expect(result == nil)
    }

    @Test("traverses parent directories for jj repo")
    func jjTraversesParents() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createDir((root as NSString).appendingPathComponent(".jj"))
        let subdir = (root as NSString).appendingPathComponent("a/b/c")
        try createDir(subdir)

        let result = await VCSKind.detect(at: subdir)
        #expect(result == .jjNative)
    }

    @Test("traverses parent directories for git repo")
    func gitTraversesParents() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createDir((root as NSString).appendingPathComponent(".git"))
        let subdir = (root as NSString).appendingPathComponent("src/components")
        try createDir(subdir)

        let result = await VCSKind.detect(at: subdir)
        #expect(result == .git)
    }

    @Test("traverses parent directories for colocated jj repo")
    func colocatedJJTraversesParents() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createDir((root as NSString).appendingPathComponent(".jj"))
        try createDir((root as NSString).appendingPathComponent(".git"))
        let subdir = (root as NSString).appendingPathComponent("deep/nested")
        try createDir(subdir)

        let result = await VCSKind.detect(at: subdir)
        #expect(result == .jjColocated)
    }

    @Test("ignores .jj file and falls back to git")
    func jjFileIgnored() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createFile((root as NSString).appendingPathComponent(".jj"))
        try createDir((root as NSString).appendingPathComponent(".git"))

        let result = await VCSKind.detect(at: root)
        #expect(result == .git)
    }

    @Test("ignores .jj file in parent and continues traversal")
    func jjFileIgnoredTraversalContinues() async throws {
        let root = try makeTempDir()
        defer { cleanup(root) }
        try createFile((root as NSString).appendingPathComponent(".jj"))
        let parent = (root as NSString).appendingPathComponent("parent")
        try createDir(parent)
        try createDir((parent as NSString).appendingPathComponent(".git"))
        let child = (parent as NSString).appendingPathComponent("child")
        try createDir(child)

        let result = await VCSKind.detect(at: child)
        #expect(result == .git)
    }

    @Test("stops at first repo boundary when nested")
    func stopsAtNearestRepo() async throws {
        let outer = try makeTempDir()
        defer { cleanup(outer) }
        try createDir((outer as NSString).appendingPathComponent(".git"))

        let inner = (outer as NSString).appendingPathComponent("inner")
        try createDir(inner)
        try createDir((inner as NSString).appendingPathComponent(".jj"))

        let deep = (inner as NSString).appendingPathComponent("deep")
        try createDir(deep)

        let result = await VCSKind.detect(at: deep)
        #expect(result == .jjNative)
    }

    @Test("isJujutsu is true for jjNative")
    func isJujutsuNative() {
        #expect(VCSKind.jjNative.isJujutsu == true)
    }

    @Test("isJujutsu is true for jjColocated")
    func isJujutsuColocated() {
        #expect(VCSKind.jjColocated.isJujutsu == true)
    }

    @Test("isJujutsu is false for git")
    func isJujutsuGit() {
        #expect(VCSKind.git.isJujutsu == false)
    }

    @Test("display names are correct")
    func displayNames() {
        #expect(VCSKind.git.displayName == "Git")
        #expect(VCSKind.jjNative.displayName == "Jujutsu")
        #expect(VCSKind.jjColocated.displayName == "Jujutsu (colocated)")
    }
}
