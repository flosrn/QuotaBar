import Testing
@testable import QuotaCore

// FORK(flosrn): removing the default Claude sign-in moves whatever read it.
@Suite struct ForkClaudeDefaultSignIn {
    @Test func removingDefaultMovesCardToFirstListedSignIn() {
        var prefs = ExperiencePrefs()
        let listed = [LocalCredentials.claudeService, "Claude Code-credentials-65404dee", "Claude Code-credentials-8c958809"]
        #expect(prefs.claudeItem == LocalCredentials.claudeService)
        prefs.forgetClaudeSignIn(LocalCredentials.claudeService)
        prefs.forkMoveOffHiddenClaudeSignIns(available: listed)
        #expect(prefs.hiddenClaudeSignIns.contains(LocalCredentials.claudeService))
        #expect(prefs.claudeItem == "Claude Code-credentials-65404dee")
    }

    @Test func removingAnExtraWhileOnItKeepsOtherChoiceRules() {
        var prefs = ExperiencePrefs()
        prefs.hiddenClaudeSignIns = [LocalCredentials.claudeService]
        prefs.claudeSignInChoice = "Claude Code-credentials-8c958809"
        let listed = ["Claude Code-credentials-65404dee", "Claude Code-credentials-8c958809"]
        prefs.forgetClaudeSignIn("Claude Code-credentials-8c958809")
        prefs.forkMoveOffHiddenClaudeSignIns(available: listed)
        #expect(prefs.claudeItem == "Claude Code-credentials-65404dee")
    }

    @Test func removingAnUnusedExtraLeavesCardAlone() {
        var prefs = ExperiencePrefs()
        prefs.claudeSignInChoice = "Claude Code-credentials-8c958809"
        prefs.forgetClaudeSignIn("Claude Code-credentials-65404dee")
        prefs.forkMoveOffHiddenClaudeSignIns(available: [LocalCredentials.claudeService, "Claude Code-credentials-65404dee", "Claude Code-credentials-8c958809"])
        #expect(prefs.claudeItem == "Claude Code-credentials-8c958809")
    }
}
