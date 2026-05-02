import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "JujutsuWorkspace")

actor JujutsuWorkspaceService {
    static let shared = JujutsuWorkspaceService()

    enum JujutsuError: LocalizedError {
        case notJujutsuRepository
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notJujutsuRepository:
                "This folder is not a Jujutsu workspace."
            case let .commandFailed(message):
                message
            }
        }
    }

    func isJujutsuRepository(_ path: String) async -> Bool {
        let jjPath = (path as NSString).appendingPathComponent(".jj")
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: jjPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func hasUncommittedChanges(worktreePath: String) async -> Bool {
        guard let result = try? runJJ(
            repoPath: worktreePath,
            arguments: ["status", "--color=never"]
        )
        else {
            return false
        }
        guard result.status == 0 else { return false }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "The working copy is clean"
    }

    func listWorkspaces(repoPath: String) async throws -> [GitWorktreeRecord] {
        let result = try runJJ(repoPath: repoPath, arguments: ["workspace", "list", "--color=never"])
        guard result.status == 0 else {
            throw JujutsuError.commandFailed(
                result.stderr.isEmpty ? "Failed to list workspaces." : result.stderr
            )
        }
        return parseWorkspaceList(result.stdout, repoPath: repoPath)
    }

    func addWorkspace(
        repoPath: String,
        path: String,
        branch: String,
        createBranch: Bool
    ) async throws {
        let name = branch.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw JujutsuError.commandFailed("Workspace name is required.")
        }
        let relativePath = "../\(name)"
        let result = try runJJ(repoPath: repoPath, arguments: ["workspace", "add", relativePath])
        guard result.status == 0 else {
            throw JujutsuError.commandFailed(
                result.stderr.isEmpty ? "Failed to add workspace." : result.stderr
            )
        }
    }

    func forgetWorkspace(repoPath: String, path: String, force: Bool) async throws {
        let name = URL(fileURLWithPath: path).lastPathComponent
        var args = ["workspace", "forget"]
        if force { args.append("--ignore-immutable") }
        args.append(name)
        let result = try runJJ(repoPath: repoPath, arguments: args)
        guard result.status == 0 else {
            throw JujutsuError.commandFailed(
                result.stderr.isEmpty ? "Failed to forget workspace." : result.stderr
            )
        }
    }

    func deleteBranch(repoPath: String, branch: String) async throws {}

    private func parseWorkspaceList(_ raw: String, repoPath: String) -> [GitWorktreeRecord] {
        var records: [GitWorktreeRecord] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let isDefault = name == "default"
            let path: String
            if isDefault {
                path = repoPath
            } else if let resolved = resolveWorkspacePath(name: name, repoPath: repoPath) {
                path = resolved
            } else {
                continue
            }

            records.append(GitWorktreeRecord(
                path: path,
                branch: isDefault ? nil : name,
                head: nil,
                isBare: false,
                isDetached: false,
                isPrunable: false
            ))
        }

        return records
    }

    private func resolveWorkspacePath(name: String, repoPath: String) -> String? {
        let parent = URL(fileURLWithPath: repoPath).deletingLastPathComponent().path
        let siblingPath = (parent as NSString).appendingPathComponent(name)
        let jjPath = (siblingPath as NSString).appendingPathComponent(".jj")
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: jjPath, isDirectory: &isDirectory), isDirectory.boolValue {
            return siblingPath
        }
        return nil
    }

    private struct JJRunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func runJJ(repoPath: String, arguments: [String]) throws -> JJRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["jj"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return JJRunResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
