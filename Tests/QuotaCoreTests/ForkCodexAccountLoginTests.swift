import XCTest
@testable import QuotaCore

/// FORK(flosrn): an account signed in with its own CODEX_HOME is kept
/// without the CLI's sign-in being touched, and signing in again replaces it.
final class ForkCodexAccountLoginTests: XCTestCase {
    private var directory: URL!
    private var live: URL { directory.appendingPathComponent("live/auth.json") }
    private var loginDir: URL { directory.appendingPathComponent("login") }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("fork-codex-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: loginDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func jwt(_ claims: [String: Any]) -> String {
        func part(_ object: Any) -> String {
            (try! JSONSerialization.data(withJSONObject: object)).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(part(["alg": "none"])).\(part(claims)).sig"
    }

    private func authFile(_ account: String, email: String, refresh: String) -> Data {
        let root: [String: Any] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "tokens": [
                "id_token": jwt(["email": email, "https://api.openai.com/auth": ["chatgpt_plan_type": "pro", "chatgpt_account_id": account]]),
                "access_token": jwt(["exp": now.addingTimeInterval(9 * 86_400).timeIntervalSince1970]),
                "refresh_token": refresh,
                "account_id": account,
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testAnOutsideSignInIsKeptWithoutTouchingTheCLIsAndReplacedOnRelogin() async throws {
        let cli = authFile("acct-cli", email: "cli@example.com", refresh: "rt-cli")
        try cli.write(to: live)
        let storage = MemoryCredentialStorage()
        let vault = CodexAccountVault(liveURL: live, storage: storage, refresher: { _ in
            XCTFail("no refresh expected"); return .init()
        })

        XCTAssertNil(CodexAccountLogin.signIn(in: loginDir), "nothing until codex login writes auth.json")
        try authFile("acct-new", email: "new@example.com", refresh: "rt-1").write(to: loginDir.appendingPathComponent("auth.json"))
        let file = try XCTUnwrap(CodexAccountLogin.signIn(in: loginDir))
        let kept = try await vault.keep(signIn: file, now: now)
        XCTAssertEqual(kept.id, "acct-new")
        XCTAssertEqual(kept.email, "new@example.com")

        try authFile("acct-new", email: "new@example.com", refresh: "rt-2").write(to: loginDir.appendingPathComponent("auth.json"))
        try await vault.keep(signIn: XCTUnwrap(CodexAccountLogin.signIn(in: loginDir)), now: now.addingTimeInterval(60))

        let accounts = await vault.accounts()
        XCTAssertEqual(accounts.map(\.id), ["acct-new"])
        XCTAssertEqual(accounts.first?.savedAt, now, "a re-login keeps when it was first saved")
        let blob = await vault.stored("acct-new")
        XCTAssertEqual(blob?.refreshToken, "rt-2")
        XCTAssertEqual(try Data(contentsOf: live), cli, "the CLI's sign-in is untouched")
        let read = try await vault.credentials(for: "acct-new", now: now)
        XCTAssertEqual(read.refreshToken, "rt-2")
    }

    func testTheLoginScriptUsesItsOwnHomeAndTheFileStore() throws {
        let prepared = try CodexAccountLogin.prepare(home: directory)
        let script = try String(contentsOf: prepared.command, encoding: .utf8)
        XCTAssertTrue(script.contains("export CODEX_HOME='\(prepared.directory.path)'"))
        XCTAssertTrue(script.contains("cli_auth_credentials_store=\"file\""))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: prepared.command.path))
        CodexAccountLogin.discard(prepared.directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.directory.path))
    }

    /// A sign-in finished after the app stopped waiting — the folder even
    /// re-made by `codex login` — is still kept, and only then removed.
    func testLateLoginsAreSweptAndUnfinishedOnesWait() async throws {
        let home = directory.appendingPathComponent("home")
        let finished = home.appendingPathComponent(".codex-quotabar-login-late")
        let waiting = home.appendingPathComponent(".codex-quotabar-login-waiting")
        try FileManager.default.createDirectory(at: finished, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: waiting, withIntermediateDirectories: true)
        try authFile("acct-late", email: "late@example.com", refresh: "rt-late").write(to: finished.appendingPathComponent("auth.json"))
        let vault = CodexAccountVault(liveURL: live, storage: MemoryCredentialStorage(), refresher: { _ in
            XCTFail("no refresh expected"); return .init()
        })

        // The real clock: the folders were made just now, and an empty one is cleared only after a day.
        let result = await vault.importLogins(home: home, now: Date())

        XCTAssertEqual(result.kept.map(\.email), ["late@example.com"])
        XCTAssertTrue(result.failed.isEmpty)
        let accounts = await vault.accounts()
        XCTAssertEqual(accounts.map(\.id), ["acct-late"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: finished.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: waiting.path), "a login still in progress is left alone")
    }
}
