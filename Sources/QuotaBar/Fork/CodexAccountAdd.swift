import AppKit
import QuotaCore

// FORK(flosrn): the Codex "Add account" button. See FORK.md and
// QuotaCore/Fork/CodexAccountLogin.swift.
extension UsageStore {
    /// Opens `codex login` in Terminal with a throwaway CODEX_HOME, then keeps
    /// the account it signs in as. The CLI's own sign-in is left alone.
    func addCodexAccount() {
        let prepared: CodexAccountLogin.Prepared
        do {
            prepared = try CodexAccountLogin.prepare()
        } catch {
            codexSwitchNotice = error.localizedDescription
            return
        }
        guard NSWorkspace.shared.open(prepared.command) else {
            CodexAccountLogin.discard(prepared.directory)
            codexSwitchNotice = L10n.t("Could not open the login window.", "无法打开登录窗口。")
            return
        }
        codexSwitchNotice = L10n.t(
            "Sign in in the Terminal window; the account is kept here once it is done.",
            "请在终端窗口里登录，完成后账号会自动保存。")
        // Picked up at once while this waits; a sign-in finished later is
        // picked up by the next Codex refresh (`importCodexLogins`), so the
        // folder is never removed from under a login still in progress.
        Task { [weak self] in
            for _ in 0..<300 {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard CodexAccountLogin.signIn(in: prepared.directory) != nil else { continue }
                await self?.importCodexLogins()
                return
            }
        }
    }

    /// Keeps every finished Add-account login, then reads the accounts again.
    func importCodexLogins() async {
        let result = await codexAccounts.vault.importLogins()
        guard !result.kept.isEmpty || !result.failed.isEmpty else { return }
        await codexAccounts.readOthers()
        if let error = result.failed.first {
            codexSwitchNotice = error.localizedDescription
        } else {
            let names = result.kept.map { codexAccounts.label($0, masked: isPrivacyMasked) }.joined(separator: ", ")
            codexSwitchNotice = L10n.t("Saved \(names).", "已保存 \(names)。")
        }
    }
}
