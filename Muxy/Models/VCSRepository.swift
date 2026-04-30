import Foundation

protocol VCSWorktreeRecordProtocol: Sendable {
    var path: String { get }
    var branch: String? { get }
    var head: String? { get }
}

protocol VCSWorktreeListing {
    func listWorktrees(repoPath: String) async throws -> [any VCSWorktreeRecordProtocol]
    func isRepository(_ path: String) async -> Bool
    func hasUncommittedChanges(worktreePath: String) async -> Bool
}

protocol VCSRepositoryServiceProtocol {
    func currentBranch(repoPath: String) async throws -> String
    func headSha(repoPath: String) async -> String?
    func listBranches(repoPath: String) async throws -> [String]
    func switchBranch(repoPath: String, branch: String) async throws
    func createAndSwitchBranch(repoPath: String, name: String) async throws
    func changedFiles(repoPath: String) async throws -> [VCSStatusFile]
    func stageFiles(repoPath: String, paths: [String]) async throws
    func stageAll(repoPath: String) async throws
    func unstageFiles(repoPath: String, paths: [String]) async throws
    func unstageAll(repoPath: String) async throws
    func discardFiles(repoPath: String, paths: [String], untrackedPaths: [String]) async throws
    func discardAll(repoPath: String) async throws
    func commit(repoPath: String, message: String) async throws -> String
    func push(repoPath: String) async throws
    func pushSetUpstream(repoPath: String, branch: String) async throws
    func pull(repoPath: String) async throws
    func commitLog(repoPath: String, maxCount: Int, skip: Int) async throws -> [VCSCommit]
    func aheadBehind(repoPath: String, branch: String) async -> VCSAheadBehind
    func defaultBranch(repoPath: String) async -> String?
    func remoteWebURL(repoPath: String) async -> URL?
    func cherryPick(repoPath: String, hash: String) async throws
    func revert(repoPath: String, hash: String) async throws
    func createBranch(repoPath: String, name: String, startPoint: String) async throws
    func createTag(repoPath: String, name: String, hash: String) async throws
    func checkoutDetached(repoPath: String, hash: String) async throws
}

struct VCSStatusFile: Identifiable, Hashable {
    let path: String
    let oldPath: String?
    let xStatus: Character
    let yStatus: Character
    let additions: Int?
    let deletions: Int?
    let isBinary: Bool

    var id: String { path }

    var isStaged: Bool {
        let staged: Set<Character> = ["A", "M", "D", "R", "C"]
        return staged.contains(xStatus)
    }

    var isUnstaged: Bool {
        let unstaged: Set<Character> = ["M", "D", "?"]
        return unstaged.contains(yStatus) || (xStatus == "?" && yStatus == "?")
    }

    var statusText: String {
        switch (xStatus, yStatus) {
        case ("A", _),
             (_, "A"):
            "A"
        case ("D", _),
             (_, "D"):
            "D"
        case ("R", _),
             (_, "R"):
            "R"
        case ("C", _),
             (_, "C"):
            "C"
        case ("M", _),
             (_, "M"):
            "M"
        case ("U", _),
             (_, "U"):
            "U"
        default:
            "?"
        }
    }

    var stagedStatusText: String {
        String(xStatus)
    }

    var unstagedStatusText: String {
        if xStatus == "?", yStatus == "?" {
            return "U"
        }
        return String(yStatus)
    }
}

struct VCSCommit: Identifiable, Hashable {
    let hash: String
    let shortHash: String
    let subject: String
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let body: String
    let refs: [GitRef]
    let parentHashes: [String]

    var id: String { hash }
    var isMerge: Bool { parentHashes.count > 1 }
}

struct VCSAheadBehind: Equatable {
    let ahead: Int
    let behind: Int
    let hasUpstream: Bool
}

enum VCSError: LocalizedError {
    case notRepository
    case noUpstreamBranch
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRepository:
            "This folder is not a version-controlled repository."
        case .noUpstreamBranch:
            "The current branch has no upstream branch on the remote."
        case let .commandFailed(message):
            message
        }
    }
}
