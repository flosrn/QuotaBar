import Foundation

// FORK(flosrn): the default Claude Code sign-in (`Claude Code-credentials`,
// no CLAUDE_CONFIG_DIR) is removable like the others. See FORK.md.

extension ExperiencePrefs {
    /// Whatever read a sign-in that is now hidden — the arrow's choice, a
    /// profile — moves to the first sign-in of `services` still shown. Without
    /// this, `claudeItem` falls back to the default sign-in, which may be the
    /// one just removed.
    public mutating func forkMoveOffHiddenClaudeSignIns(available services: [String]) {
        guard let next = services.first(where: { !hiddenClaudeSignIns.contains($0) }) else { return }
        let item: String? = next == LocalCredentials.claudeService ? nil : next
        if hiddenClaudeSignIns.contains(claudeSignInChoice ?? LocalCredentials.claudeService) {
            claudeSignInChoice = item
        }
        for index in accountProfiles.indices where hiddenClaudeSignIns.contains(accountProfiles[index].claudeItem) {
            accountProfiles[index].claudeService = item
        }
    }
}
