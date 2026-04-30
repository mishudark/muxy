import Foundation

struct JJRepositoryService: VCSRepositoryServiceProtocol {
    struct PatchAndCompareResult {
        let rows: [DiffDisplayRow]
        let truncated: Bool
        let additions: Int
        let deletions: Int
    }

    func currentBranch(repoPath: String) async throws -> String {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["bookmark", "list", "-r", "@", "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed("Failed to get current bookmark.")
        }
        if let bookmark = parseBookmarkName(from: result.stdout), !bookmark.isEmpty {
            return bookmark
        }
        return await headSha(repoPath: repoPath) ?? ""
    }

    func headSha(repoPath: String) async -> String? {
        let result = try? await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["log", "--no-graph", "-r", "@", "-T", "change_id", "--no-pager"]
        )
        guard let result, result.status == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func listBranches(repoPath: String) async throws -> [String] {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["bookmark", "list", "--all", "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to list bookmarks." : result.stderr)
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("@") else { return nil }
                return parseBookmarkName(from: trimmed)
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func switchBranch(repoPath: String, branch: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["bookmark", "track", branch]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to switch bookmark." : result.stderr)
        }
    }

    func createAndSwitchBranch(repoPath: String, name: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["bookmark", "create", "-r", "@", name]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to create bookmark." : result.stderr)
        }
    }

    func changedFiles(repoPath: String) async throws -> [VCSStatusFile] {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["diff", "--stat", "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to load status." : result.stderr)
        }
        return parseDiffStat(result.stdout)
    }

    func stageFiles(repoPath: String, paths: [String]) async throws {
        for path in paths {
            let result = try await JJProcessRunner.runJJ(
                repoPath: repoPath,
                arguments: ["squash", "-i", path, "--no-pager"]
            )
            guard result.status == 0 else {
                throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to stage file." : result.stderr)
            }
        }
    }

    func stageAll(repoPath: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["squash", "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to stage all." : result.stderr)
        }
    }

    func unstageFiles(repoPath: String, paths: [String]) async throws {
        for path in paths {
            let result = try await JJProcessRunner.runJJ(
                repoPath: repoPath,
                arguments: ["unsquash", "-i", path, "--no-pager"]
            )
            guard result.status == 0 else {
                throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to unstage file." : result.stderr)
            }
        }
    }

    func unstageAll(repoPath: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["unsquash", "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to unstage all." : result.stderr)
        }
    }

    func discardFiles(repoPath: String, paths: [String], untrackedPaths: [String]) async throws {
        for path in paths {
            let result = try await JJProcessRunner.runJJ(
                repoPath: repoPath,
                arguments: ["restore", path, "--no-pager"]
            )
            guard result.status == 0 else {
                throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to discard changes." : result.stderr)
            }
        }
        for path in untrackedPaths {
            let fullPath = (repoPath as NSString).appendingPathComponent(path)
            try FileManager.default.removeItem(atPath: fullPath)
        }
    }

    func discardAll(repoPath: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["restore", "--all", "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to discard all changes." : result.stderr)
        }
    }

    func commit(repoPath: String, message: String) async throws -> String {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["describe", "-m", message]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to describe change." : result.stderr)
        }
        let newResult = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["new", "--no-pager"]
        )
        guard newResult.status == 0 else {
            throw VCSError.commandFailed(newResult.stderr.isEmpty ? "Failed to create new change." : newResult.stderr)
        }
        let head = await headSha(repoPath: repoPath)
        return head ?? ""
    }

    func push(repoPath: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["git", "push", "--no-pager"]
        )
        guard result.status == 0 else {
            if result.stderr.contains("has no upstream branch") {
                throw VCSError.noUpstreamBranch
            }
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to push." : result.stderr)
        }
    }

    func pushSetUpstream(repoPath: String, branch: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["git", "push", "-b", branch, "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to push." : result.stderr)
        }
    }

    func pull(repoPath: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["git", "fetch", "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to fetch." : result.stderr)
        }
    }

    func commitLog(repoPath: String, maxCount: Int, skip: Int) async throws -> [VCSCommit] {
        let template = "change_id ++ \"\\n\" ++ commit_id.short(8) ++ \"\\n\" ++ description.first_line() ++ \"\\n\" ++ author.name() ++ \"\\n\" ++ author.email() ++ \"\\n\" ++ author.timestamp() ++ \"\\n\" ++ description ++ \"\\n\" ++ branches ++ \"\\n==END==\\n\""
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["log", "--no-graph", "-T", template, "--limit", String(maxCount), "--skip", String(skip), "--no-pager"]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to load log." : result.stderr)
        }
        return parseCommitLog(result.stdout)
    }

    func aheadBehind(repoPath: String, branch: String) async -> VCSAheadBehind {
        guard !branch.isEmpty else {
            return VCSAheadBehind(ahead: 0, behind: 0, hasUpstream: false)
        }

        let listResult = try? await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["bookmark", "list", branch, "--no-pager"]
        )
        guard let listResult, listResult.status == 0 else {
            return VCSAheadBehind(ahead: 0, behind: 0, hasUpstream: false)
        }

        var remoteRef: String?
        for line in listResult.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("@origin:") {
                remoteRef = "origin/\(branch)"
                break
            } else if trimmed.hasPrefix("@git:") {
                remoteRef = "git/\(branch)"
                break
            }
        }
        guard let remoteRef else {
            return VCSAheadBehind(ahead: 0, behind: 0, hasUpstream: false)
        }

        let aheadResult = try? await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["log", "--no-graph", "-T", "change_id\n", "-r", "\(remoteRef)..\(branch)", "--no-pager"]
        )
        let ahead = aheadResult?.stdout.split(separator: "\n", omittingEmptySubsequences: true).count ?? 0
        let behindResult = try? await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["log", "--no-graph", "-T", "change_id\n", "-r", "\(branch)..\(remoteRef)", "--no-pager"]
        )
        let behind = behindResult?.stdout.split(separator: "\n", omittingEmptySubsequences: true).count ?? 0

        return VCSAheadBehind(ahead: ahead, behind: behind, hasUpstream: true)
    }

    func defaultBranch(repoPath: String) async -> String? {
        let result = try? await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["bookmark", "list", "--remote", "origin", "--no-pager"]
        )
        guard let result, result.status == 0 else { return nil }
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("@") else { continue }
            if let name = parseBookmarkName(from: trimmed), name == "main" || name == "master" {
                return name
            }
        }
        return lines.first.flatMap { parseBookmarkName(from: String($0)) }
    }

    func remoteWebURL(repoPath: String) async -> URL? {
        let result = try? await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["git", "remote", "list", "--no-pager"]
        )
        guard let result, result.status == 0 else { return nil }
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let raw = String(parts[1])
            return GitRepositoryService.webURL(fromRemoteURL: raw)
        }
        return nil
    }

    func cherryPick(repoPath: String, hash: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["new", "-A", hash]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to cherry-pick." : result.stderr)
        }
    }

    func revert(repoPath: String, hash: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["backout", "-r", hash]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to revert." : result.stderr)
        }
    }

    func createBranch(repoPath: String, name: String, startPoint: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["bookmark", "create", "-r", startPoint, name]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to create bookmark." : result.stderr)
        }
    }

    func createTag(repoPath: String, name: String, hash: String) async throws {
        throw VCSError.commandFailed("Tags not supported in Jujutsu yet.")
    }

    func checkoutDetached(repoPath: String, hash: String) async throws {
        let result = try await JJProcessRunner.runJJ(
            repoPath: repoPath,
            arguments: ["new", hash]
        )
        guard result.status == 0 else {
            throw VCSError.commandFailed(result.stderr.isEmpty ? "Failed to checkout." : result.stderr)
        }
    }

    func parseBookmarkName(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let name = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        return parts.first.map(String.init)
    }

    func parseDiffStat(_ raw: String) -> [VCSStatusFile] {
        var files: [VCSStatusFile] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("+") else { continue }
            let parts = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true)
            guard let pathPart = parts.first else { continue }
            let path = String(pathPart).trimmingCharacters(in: .whitespaces)
            var additions: Int?
            var deletions: Int?
            if parts.count > 1 {
                let stats = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if stats == "Binary" {
                    additions = nil
                    deletions = nil
                } else {
                    additions = stats.filter { $0 == "+" }.count
                    deletions = stats.filter { $0 == "-" }.count
                }
            }
            files.append(VCSStatusFile(
                path: path,
                oldPath: nil,
                xStatus: " ",
                yStatus: "M",
                additions: additions,
                deletions: deletions,
                isBinary: additions == nil && deletions == nil
            ))
        }
        return files
    }

    func parseCommitLog(_ raw: String) -> [VCSCommit] {
        var commits: [VCSCommit] = []
        let blocks = raw.components(separatedBy: "==END==")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 7 else { continue }
            let hash = String(lines[0]).trimmingCharacters(in: .whitespaces)
            let shortHash = String(lines[1]).trimmingCharacters(in: .whitespaces)
            let subject = String(lines[2]).trimmingCharacters(in: .whitespaces)
            let authorName = String(lines[3]).trimmingCharacters(in: .whitespaces)
            let authorEmail = String(lines[4]).trimmingCharacters(in: .whitespaces)
            let timestamp = String(lines[5]).trimmingCharacters(in: .whitespaces)
            let refsRaw = String(lines[6]).trimmingCharacters(in: .whitespaces)
            let body = lines.dropFirst(7).joined(separator: "\n")
            let refs: [GitRef] = refsRaw.isEmpty ? [] : refsRaw.split(separator: " ", omittingEmptySubsequences: true).compactMap { part in
                let trimmed = String(part).trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                if trimmed.hasPrefix("tags/") {
                    return GitRef(name: String(trimmed.dropFirst("tags/".count)), kind: .tag)
                }
                if trimmed.hasPrefix("origin/") {
                    return GitRef(name: String(trimmed.dropFirst("origin/".count)), kind: .remoteBranch)
                }
                return GitRef(name: trimmed, kind: .localBranch)
            }

            let date = ISO8601DateParser.parse(timestamp) ?? Date()
            commits.append(VCSCommit(
                hash: hash,
                shortHash: shortHash,
                subject: subject,
                authorName: authorName,
                authorEmail: authorEmail,
                authorDate: date,
                body: body,
                refs: refs,
                parentHashes: []
            ))
        }
        return commits
    }
}

private enum ISO8601DateParser {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
