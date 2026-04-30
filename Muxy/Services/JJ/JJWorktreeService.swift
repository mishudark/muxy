import Foundation

struct JJWorktreeRecord: VCSWorktreeRecordProtocol, Hashable {
    let path: String
    let branch: String?
    let head: String?
}

actor JJWorktreeService: VCSWorktreeListing {
    static let shared = JJWorktreeService()

    enum JJWorktreeError: LocalizedError {
        case notRepository
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notRepository:
                "This folder is not a Jujutsu repository."
            case let .commandFailed(message):
                message
            }
        }
    }

    func isRepository(_ path: String) async -> Bool {
        guard let result = try? await runJJ(repoPath: path, arguments: ["root"]) else {
            return false
        }
        return result.status == 0
    }

    func hasUncommittedChanges(worktreePath: String) async -> Bool {
        guard let result = try? await runJJ(
            repoPath: worktreePath,
            arguments: ["status", "--no-pager"]
        )
        else {
            return false
        }
        guard result.status == 0 else { return false }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func listWorktrees(repoPath: String) async throws -> [any VCSWorktreeRecordProtocol] {
        let result = try await runJJ(repoPath: repoPath, arguments: ["workspace", "list", "--no-pager"])
        guard result.status == 0 else {
            throw JJWorktreeError.commandFailed(
                result.stderr.isEmpty ? "Failed to list workspaces." : result.stderr
            )
        }
        return parseWorkspaceList(result.stdout, repoPath: repoPath)
    }

    func addWorktree(repoPath: String, path: String, branch: String, createBranch: Bool) async throws {
        var args: [String] = ["workspace", "add"]
        if createBranch {
            args += ["--revision", branch]
        }
        args += [path]
        let result = try await runJJ(repoPath: repoPath, arguments: args)
        guard result.status == 0 else {
            throw JJWorktreeError.commandFailed(
                result.stderr.isEmpty ? "Failed to add workspace." : result.stderr
            )
        }
    }

    func removeWorktree(repoPath: String, path: String) async throws {
        let result = try await runJJ(repoPath: repoPath, arguments: ["workspace", "forget", path])
        guard result.status == 0 else {
            throw JJWorktreeError.commandFailed(
                result.stderr.isEmpty ? "Failed to remove workspace." : result.stderr
            )
        }
    }

    private func parseWorkspaceList(_ raw: String, repoPath: String) -> [JJWorktreeRecord] {
        var records: [JJWorktreeRecord] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let workspacePath = String(parts[0])
            let branch = parts.count > 1 ? String(parts[1]) : nil
            let normalizedPath: String
            if workspacePath.hasPrefix("/") {
                normalizedPath = workspacePath
            } else {
                normalizedPath = (repoPath as NSString).appendingPathComponent(workspacePath)
            }
            records.append(JJWorktreeRecord(path: normalizedPath, branch: branch, head: nil))
        }
        return records
    }

    private func runJJ(repoPath: String, arguments: [String]) async throws -> JJProcessResult {
        try await JJProcessRunner.runJJ(repoPath: repoPath, arguments: arguments)
    }
}
