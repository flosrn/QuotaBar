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
        Task { [weak self] in
            defer { CodexAccountLogin.discard(prepared.directory) }
            // Up to ten minutes, as the Claude login waits.
            for _ in 0..<300 {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let file = CodexAccountLogin.signIn(in: prepared.directory) else { continue }
                guard let self else { return }
                do {
                    let account = try await self.codexAccounts.vault.keep(signIn: file)
                    await self.codexAccounts.readOthers()
                    let name = self.codexAccounts.label(account, masked: self.isPrivacyMasked)
                    self.codexSwitchNotice = L10n.t("Saved \(name).", "已保存 \(name)。")
                } catch {
                    self.codexSwitchNotice = error.localizedDescription
                }
                return
            }
            self?.codexSwitchNotice = nil
        }
    }
}
