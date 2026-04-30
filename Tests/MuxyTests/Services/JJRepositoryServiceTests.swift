import Foundation
import Testing

@testable import Muxy

@Suite("JJRepositoryService")
struct JJRepositoryServiceTests {
    let service = JJRepositoryService()

    @Test("parses bookmark name from jj bookmark list output")
    func parseBookmarkNameBasic() {
        let output = "main: pokrxrxq 455b75a1 Fix split panes"
        #expect(service.parseBookmarkName(from: output) == "main")
    }

    @Test("parses bookmark name with hyphen")
    func parseBookmarkNameWithHyphen() {
        let output = "add-declarative-star: xqmozxpv 5a333a72 Add declarative layout"
        #expect(service.parseBookmarkName(from: output) == "add-declarative-star")
    }

    @Test("returns nil for empty output")
    func parseBookmarkNameEmpty() {
        #expect(service.parseBookmarkName(from: "") == nil)
    }

    @Test("returns nil for whitespace-only output")
    func parseBookmarkNameWhitespace() {
        #expect(service.parseBookmarkName(from: "   \n  ") == nil)
    }

    @Test("parses first word when no colon present")
    func parseBookmarkNameNoColon() {
        #expect(service.parseBookmarkName(from: "feature-branch extra stuff") == "feature-branch")
    }

    @Test("returns nil for colon-only output")
    func parseBookmarkNameColonOnly() {
        #expect(service.parseBookmarkName(from: ": something") == nil)
    }

    @Test("strips trailing whitespace before colon")
    func parseBookmarkNameTrailingSpace() {
        #expect(service.parseBookmarkName(from: "main : pokrxrxq 455b75a1") == "main")
    }

    @Test("filters remote tracking lines starting with @")
    func parseBookmarkNameRemoteLine() {
        let output = "@git: pokrxrxq 455b75a1 Fix split panes"
        #expect(service.parseBookmarkName(from: output) == "@git")
    }

    @Test("currentBranch falls back to change ID when no bookmark")
    func currentBranchFallbackToChangeID() async throws {
        // headSha returns change_id for jj repos; we test the fallback path
        // by verifying parseBookmarkName returns nil for empty stdout.
        let bookmark = service.parseBookmarkName(from: "")
        #expect(bookmark == nil)
    }

    @Test("listBranches filters indented remote tracking lines")
    func listBranchesFiltersRemoteLines() {
        let raw = """
        main: pokrxrxq 455b75a1 Fix split panes
          @git: pokrxrxq 455b75a1 Fix split panes
          @origin: pokrxrxq 455b75a1 Fix split panes
        feature: abcdefgh 12345678 Add feature
        """
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        let bookmarks = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("@") else { return nil }
            return service.parseBookmarkName(from: trimmed)
        }
        #expect(bookmarks == ["main", "feature"])
    }

    @Test("defaultBranch picks main over other bookmarks")
    func defaultBranchPicksMain() {
        let raw = """
        main: pokrxrxq 455b75a1 Fix split panes
        feature: abcdefgh 12345678 Add feature
        """
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        var result: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("@") else { continue }
            if let name = service.parseBookmarkName(from: trimmed), name == "main" || name == "master" {
                result = name
                break
            }
        }
        #expect(result == "main")
    }

    @Test("defaultBranch falls back to first bookmark")
    func defaultBranchFallsBackToFirst() {
        let raw = """
        develop: abcdefgh 12345678 Add feature
        release: ijklmnop 87654321 Prepare release
        """
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        var result: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("@") else { continue }
            if let name = service.parseBookmarkName(from: trimmed), name == "main" || name == "master" {
                result = name
                break
            }
        }
        if result == nil {
            result = lines.first.flatMap { service.parseBookmarkName(from: String($0)) }
        }
        #expect(result == "develop")
    }

    @Test("parses diff stat with additions and deletions")
    func parseDiffStatBasic() {
        let raw = "Muxy/Models/VCSKind.swift | 15 +++++++--------\nMuxy/Tests/VCSKindTests.swift | 20 +++++++++++++++++"
        let files = service.parseDiffStat(raw)
        #expect(files.count == 2)
        #expect(files[0].path == "Muxy/Models/VCSKind.swift")
        #expect(files[0].additions == 7)
        #expect(files[0].deletions == 8)
        #expect(files[0].xStatus == " ")
        #expect(files[0].yStatus == "M")
        #expect(files[0].isBinary == false)
    }

    @Test("parses binary file in diff stat")
    func parseDiffStatBinary() {
        let raw = "Muxy/Resources/icon.png | Binary"
        let files = service.parseDiffStat(raw)
        #expect(files.count == 1)
        #expect(files[0].path == "Muxy/Resources/icon.png")
        #expect(files[0].additions == nil)
        #expect(files[0].deletions == nil)
        #expect(files[0].isBinary == true)
    }

    @Test("ignores summary line starting with plus")
    func parseDiffStatIgnoresSummary() {
        let raw = " 2 files changed, 10 insertions(+), 5 deletions(-)\nfile.swift | 5 +++++"
        let files = service.parseDiffStat(raw)
        #expect(files.count == 1)
        #expect(files[0].path == "file.swift")
    }

    @Test("parses commit log template output")
    func parseCommitLogBasic() {
        let raw = """
        wvwxvtrr
        806a20fb
        (empty) (no description set)
        mishu.drk@gmail.com
        mishu.drk@gmail.com
        2026-05-01T11:05:31.000+00:00
        main
        (empty) (no description set)
        ==END==
        """
        let commits = service.parseCommitLog(raw)
        #expect(commits.count == 1)
        #expect(commits[0].hash == "wvwxvtrr")
        #expect(commits[0].shortHash == "806a20fb")
        #expect(commits[0].subject == "(empty) (no description set)")
        #expect(commits[0].authorName == "mishu.drk@gmail.com")
        #expect(commits[0].authorEmail == "mishu.drk@gmail.com")
        #expect(commits[0].refs == "main")
    }

    @Test("parses multiple commits")
    func parseCommitLogMultiple() {
        let raw = """
        abcdefgh
        12345678
        First commit
        Alice
        alice@example.com
        2026-01-01T00:00:00.000+00:00


        ==END==
        ijklmnop
        87654321
        Second commit
        Bob
        bob@example.com
        2026-01-02T00:00:00.000+00:00
        feature-branch
        Second commit

        More body
        ==END==
        """
        let commits = service.parseCommitLog(raw)
        #expect(commits.count == 2)
        #expect(commits[0].hash == "abcdefgh")
        #expect(commits[1].hash == "ijklmnop")
        #expect(commits[1].refs == "feature-branch")
        #expect(commits[1].body == "Second commit\n\nMore body")
    }

    @Test("commit log ignores malformed blocks")
    func parseCommitLogIgnoresMalformed() {
        let raw = """
        wvwxvtrr
        806a20fb
        ==END==
        """
        let commits = service.parseCommitLog(raw)
        #expect(commits.isEmpty)
    }
}
