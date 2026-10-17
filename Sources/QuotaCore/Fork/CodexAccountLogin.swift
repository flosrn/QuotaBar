import Foundation

// FORK(flosrn): add a Codex account without signing the CLI in as it.
// `codex login` runs with its own throwaway CODEX_HOME, so ~/.codex/auth.json
// is never touched; the sign-in it leaves there is kept in the vault and the
// folder deleted. QuotaBar is then the only holder of that refresh token,
// which the vault refreshes on its own (`CodexAccountVault.credentials`).
// See FORK.md.
public enum CodexAccountLogin {
    public struct Prepared: Sendable {
        public let directory: URL
        public let command: URL
    }

    /// A private folder and the Terminal script that signs in into it.
    public static func prepare(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Prepared {
        let directory = home.appendingPathComponent(".codex-quotabar-login-\(UUID().uuidString.lowercased())", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let command = directory.appendingPathComponent("login.command")
        try Data(script(directory: directory).utf8).write(to: command, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
        return Prepared(directory: directory, command: command)
    }

    /// An interactive login shell: the CLI may be a pnpm or npm shim that
    /// needs the owner's own PATH (nvm, fnm) to find node.
    static func script(directory: URL) -> String {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        #!/bin/zsh -il
        unset OPENAI_API_KEY CODEX_API_KEY
        export CODEX_HOME=\(quote(directory.path))
        cd \(quote(directory.path)) || exit 1
        codex login -c 'cli_auth_credentials_store="file"' && print "\\nQuotaBar saves this account now. You can close this window."

        """
    }

    static let folderPrefix = ".codex-quotabar-login-"

    /// Every login folder this Mac has, finished or not. A browser sign-in
    /// can take longer than any wait, and the app can quit meanwhile; the
    /// folders are what is left to pick up.
    public static func folders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { $0.hasPrefix(folderPrefix) }
            .map { home.appendingPathComponent($0, isDirectory: true) }
    }

    /// The sign-in `codex login` left in `directory`, once it has.
    public static func signIn(in directory: URL) -> CodexAuthFile? {
        (try? Data(contentsOf: directory.appendingPathComponent("auth.json"))).flatMap(CodexAuthFile.init)
    }

    public static func discard(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension CodexAccountVault {
    /// Keeps a sign-in made outside ~/.codex, as if it had been saved there.
    /// Throws unless both the sign-in and the list of accounts were written:
    /// the list is what Settings and the dock read.
    @discardableResult
    public func keep(signIn file: CodexAuthFile, now: Date = .now) throws -> CodexAccount {
        let account = try keep(file, now: now)
        guard accounts().contains(where: { $0.id == account.id }) else { throw CodexAccountError.keychain }
        return account
    }

    /// Keeps every finished login folder's sign-in and removes the folder;
    /// a folder whose sign-in could not be kept stays for the next try. An
    /// unfinished one is removed after a day.
    public func importLogins(home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = .now) -> (kept: [CodexAccount], failed: [Error]) {
        var kept: [CodexAccount] = []
        var failed: [Error] = []
        for folder in CodexAccountLogin.folders(home: home) {
            if let file = CodexAccountLogin.signIn(in: folder) {
                do {
                    kept.append(try keep(signIn: file, now: now))
                    CodexAccountLogin.discard(folder)
                } catch {
                    failed.append(error)
                }
            } else if let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                      now.timeIntervalSince(created) > 86_400 {
                CodexAccountLogin.discard(folder)
            }
        }
        return (kept, failed)
    }
}
