import Foundation

struct VCSRepositoryService: VCSRepositoryServiceProtocol {
    private let git = GitRepositoryService()
    private let jj = JJRepositoryService()

    private func resolve(repoPath: String) async -> VCSKind? {
        await VCSKind.detect(at: repoPath)
    }

    private func isJJ(_ repoPath: String) async -> Bool {
        await resolve(repoPath: repoPath)?.isJujutsu == true
    }

    func currentBranch(repoPath: String) async throws -> String {
        if await isJJ(repoPath) {
            return try await jj.currentBranch(repoPath: repoPath)
        }
        return try await git.currentBranch(repoPath: repoPath)
    }

    func headSha(repoPath: String) async -> String? {
        if await isJJ(repoPath) {
            return await jj.headSha(repoPath: repoPath)
        }
        return await git.headSha(repoPath: repoPath)
    }

    func listBranches(repoPath: String) async throws -> [String] {
        if await isJJ(repoPath) {
            return try await jj.listBranches(repoPath: repoPath)
        }
        return try await git.listBranches(repoPath: repoPath)
    }

    func switchBranch(repoPath: String, branch: String) async throws {
        if await isJJ(repoPath) {
            try await jj.switchBranch(repoPath: repoPath, branch: branch)
        } else {
            try await git.switchBranch(repoPath: repoPath, branch: branch)
        }
    }

    func createAndSwitchBranch(repoPath: String, name: String) async throws {
        if await isJJ(repoPath) {
            try await jj.createAndSwitchBranch(repoPath: repoPath, name: name)
        } else {
            try await git.createAndSwitchBranch(repoPath: repoPath, name: name)
        }
    }

    func changedFiles(repoPath: String) async throws -> [VCSStatusFile] {
        if await isJJ(repoPath) {
            return try await jj.changedFiles(repoPath: repoPath)
        }
        let gitFiles = try await git.changedFiles(repoPath: repoPath)
        return gitFiles.map { git in
            VCSStatusFile(
                path: git.path,
                oldPath: git.oldPath,
                xStatus: git.xStatus,
                yStatus: git.yStatus,
                additions: git.additions,
                deletions: git.deletions,
                isBinary: git.isBinary
            )
        }
    }

    func stageFiles(repoPath: String, paths: [String]) async throws {
        if await isJJ(repoPath) {
            try await jj.stageFiles(repoPath: repoPath, paths: paths)
        } else {
            try await git.stageFiles(repoPath: repoPath, paths: paths)
        }
    }

    func stageAll(repoPath: String) async throws {
        if await isJJ(repoPath) {
            try await jj.stageAll(repoPath: repoPath)
        } else {
            try await git.stageAll(repoPath: repoPath)
        }
    }

    func unstageFiles(repoPath: String, paths: [String]) async throws {
        if await isJJ(repoPath) {
            try await jj.unstageFiles(repoPath: repoPath, paths: paths)
        } else {
            try await git.unstageFiles(repoPath: repoPath, paths: paths)
        }
    }

    func unstageAll(repoPath: String) async throws {
        if await isJJ(repoPath) {
            try await jj.unstageAll(repoPath: repoPath)
        } else {
            try await git.unstageAll(repoPath: repoPath)
        }
    }

    func discardFiles(repoPath: String, paths: [String], untrackedPaths: [String]) async throws {
        if await isJJ(repoPath) {
            try await jj.discardFiles(repoPath: repoPath, paths: paths, untrackedPaths: untrackedPaths)
        } else {
            try await git.discardFiles(repoPath: repoPath, paths: paths, untrackedPaths: untrackedPaths)
        }
    }

    func discardAll(repoPath: String) async throws {
        if await isJJ(repoPath) {
            try await jj.discardAll(repoPath: repoPath)
        } else {
            try await git.discardAll(repoPath: repoPath)
        }
    }

    func commit(repoPath: String, message: String) async throws -> String {
        if await isJJ(repoPath) {
            return try await jj.commit(repoPath: repoPath, message: message)
        }
        return try await git.commit(repoPath: repoPath, message: message)
    }

    func push(repoPath: String) async throws {
        if await isJJ(repoPath) {
            try await jj.push(repoPath: repoPath)
        } else {
            try await git.push(repoPath: repoPath)
        }
    }

    func pushSetUpstream(repoPath: String, branch: String) async throws {
        if await isJJ(repoPath) {
            try await jj.pushSetUpstream(repoPath: repoPath, branch: branch)
        } else {
            try await git.pushSetUpstream(repoPath: repoPath, branch: branch)
        }
    }

    func pull(repoPath: String) async throws {
        if await isJJ(repoPath) {
            try await jj.pull(repoPath: repoPath)
        } else {
            try await git.pull(repoPath: repoPath)
        }
    }

    func commitLog(repoPath: String, maxCount: Int, skip: Int) async throws -> [VCSCommit] {
        if await isJJ(repoPath) {
            return try await jj.commitLog(repoPath: repoPath, maxCount: maxCount, skip: skip)
        }
        let gitCommits = try await git.commitLog(repoPath: repoPath, maxCount: maxCount, skip: skip)
        return gitCommits.map { git in
            VCSCommit(
                hash: git.hash,
                shortHash: git.shortHash,
                subject: git.subject,
                authorName: git.authorName,
                authorEmail: "",
                authorDate: git.authorDate,
                body: "",
                refs: git.refs,
                parentHashes: git.parentHashes
            )
        }
    }

    func aheadBehind(repoPath: String, branch: String) async -> VCSAheadBehind {
        if await isJJ(repoPath) {
            return await jj.aheadBehind(repoPath: repoPath, branch: branch)
        }
        let result = await git.aheadBehind(repoPath: repoPath, branch: branch)
        return VCSAheadBehind(ahead: result.ahead, behind: result.behind, hasUpstream: result.hasUpstream)
    }

    func defaultBranch(repoPath: String) async -> String? {
        if await isJJ(repoPath) {
            return await jj.defaultBranch(repoPath: repoPath)
        }
        return await git.defaultBranch(repoPath: repoPath)
    }

    func remoteWebURL(repoPath: String) async -> URL? {
        if await isJJ(repoPath) {
            return await jj.remoteWebURL(repoPath: repoPath)
        }
        return await git.remoteWebURL(repoPath: repoPath)
    }

    func cherryPick(repoPath: String, hash: String) async throws {
        if await isJJ(repoPath) {
            try await jj.cherryPick(repoPath: repoPath, hash: hash)
        } else {
            try await git.cherryPick(repoPath: repoPath, hash: hash)
        }
    }

    func revert(repoPath: String, hash: String) async throws {
        if await isJJ(repoPath) {
            try await jj.revert(repoPath: repoPath, hash: hash)
        } else {
            try await git.revert(repoPath: repoPath, hash: hash)
        }
    }

    func createBranch(repoPath: String, name: String, startPoint: String) async throws {
        if await isJJ(repoPath) {
            try await jj.createBranch(repoPath: repoPath, name: name, startPoint: startPoint)
        } else {
            try await git.createBranch(repoPath: repoPath, name: name, startPoint: startPoint)
        }
    }

    func createTag(repoPath: String, name: String, hash: String) async throws {
        if await isJJ(repoPath) {
            try await jj.createTag(repoPath: repoPath, name: name, hash: hash)
        } else {
            try await git.createTag(repoPath: repoPath, name: name, hash: hash)
        }
    }

    func checkoutDetached(repoPath: String, hash: String) async throws {
        if await isJJ(repoPath) {
            try await jj.checkoutDetached(repoPath: repoPath, hash: hash)
        } else {
            try await git.checkoutDetached(repoPath: repoPath, hash: hash)
        }
    }

    func patchAndCompare(
        repoPath: String,
        filePath: String,
        lineLimit: Int?,
        hints: GitRepositoryService.DiffHints
    ) async throws -> GitRepositoryService.PatchAndCompareResult {
        if await resolve(repoPath: repoPath) == .jjNative {
            return try await jjPatchAndCompare(repoPath: repoPath, filePath: filePath, lineLimit: lineLimit)
        }
        return try await git.patchAndCompare(repoPath: repoPath, filePath: filePath, lineLimit: lineLimit, hints: hints)
    }

    private func jjPatchAndCompare(repoPath: String, filePath: String, lineLimit: Int?) async throws -> GitRepositoryService.PatchAndCompareResult {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["diff", "-r", "@", "--", filePath]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to load diff." : result.stderr)
        }
        let patch = result.stdout
        let rows = await GitProcessRunner.offMain {
            GitDiffParser.parseRows(patch).rows
        }
        let collapsed = await GitProcessRunner.offMain {
            GitDiffParser.collapseContextRows(rows)
        }
        let additions = rows.filter { $0.kind == .addition }.count
        let deletions = rows.filter { $0.kind == .deletion }.count
        return GitRepositoryService.PatchAndCompareResult(
            rows: collapsed,
            truncated: false,
            additions: additions,
            deletions: deletions
        )
    }
}
