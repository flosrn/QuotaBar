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
    @discardableResult
    public func keep(signIn file: CodexAuthFile, now: Date = .now) throws -> CodexAccount {
        try keep(file, now: now)
    }
}
