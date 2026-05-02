import Foundation

enum VCSProviderError: LocalizedError {
    case notVCSRepository

    var errorDescription: String? {
        "This folder is not a version-controlled repository."
    }
}

actor VCSProvider {
    static let shared = VCSProvider()

    private let git = GitWorktreeService.shared
    private let jj = JujutsuWorkspaceService.shared

    private var kindCache: [String: VCSKind?] = [:]

    private func kind(for repoPath: String) async -> VCSKind? {
        if let cached = kindCache[repoPath] { return cached }
        let detected = await VCSKind.detect(at: repoPath)
        kindCache[repoPath] = detected
        return detected
    }

    func isRepository(_ path: String) async -> Bool {
        guard let kind = await kind(for: path) else { return false }
        switch kind {
        case .git: return await git.isGitRepository(path)
        case .jjColocated, .jjNative: return await jj.isJujutsuRepository(path)
        }
    }

    func listWorktrees(repoPath: String) async throws -> [GitWorktreeRecord] {
        guard let kind = await kind(for: repoPath) else {
            throw VCSProviderError.notVCSRepository
        }
        switch kind {
        case .git: return try await git.listWorktrees(repoPath: repoPath)
        case .jjColocated, .jjNative: return try await jj.listWorkspaces(repoPath: repoPath)
        }
    }

    func addWorktree(
        repoPath: String,
        path: String,
        branch: String,
        createBranch: Bool
    ) async throws {
        guard let kind = await kind(for: repoPath) else {
            throw VCSProviderError.notVCSRepository
        }
        switch kind {
        case .git:
            try await git.addWorktree(
                repoPath: repoPath,
                path: path,
                branch: branch,
                createBranch: createBranch
            )
        case .jjColocated, .jjNative:
            try await jj.addWorkspace(
                repoPath: repoPath,
                path: path,
                branch: branch,
                createBranch: createBranch
            )
        }
    }

    func removeWorktree(repoPath: String, path: String, force: Bool) async throws {
        guard let kind = await kind(for: repoPath) else {
            throw VCSProviderError.notVCSRepository
        }
        switch kind {
        case .git:
            try await git.removeWorktree(repoPath: repoPath, path: path, force: force)
        case .jjColocated, .jjNative:
            try await jj.forgetWorkspace(repoPath: repoPath, path: path, force: force)
        }
    }

    func hasUncommittedChanges(worktreePath: String) async -> Bool {
        switch await VCSKind.detect(at: worktreePath) {
        case .git:
            return await git.hasUncommittedChanges(worktreePath: worktreePath)
        case .jjColocated, .jjNative:
            return await jj.hasUncommittedChanges(worktreePath: worktreePath)
        case nil:
            return false
        }
    }

    func deleteBranch(repoPath: String, branch: String) async throws {
        guard let kind = await kind(for: repoPath) else { return }
        switch kind {
        case .git:
            try await git.deleteBranch(repoPath: repoPath, branch: branch)
        case .jjColocated, .jjNative:
            try await jj.deleteBranch(repoPath: repoPath, branch: branch)
        }
    }

    func worktreeDirectory(forProjectID projectID: UUID, name: String, projectPath: String) async -> URL {
        let kind = await self.kind(for: projectPath)
        return MuxyFileStorage.worktreeDirectory(forProjectID: projectID, name: name, projectPath: projectPath, vcsKind: kind)
    }
}
