import AppKit
import SwiftUI
import QuotaCore

// FORK(flosrn): this build is a fork, signed with a local certificate. The
// upstream updater would download an official build and refuse it (it is not
// signed by this build's team), so the fork takes the path Homebrew installs
// take: the update card still says a new version is out, and the fork is
// brought up to it by Scripts/fork/sync.sh — rebase on the release, build,
// test, package, install. See FORK.md.
enum ForkBuild {
    static let isFork = true

    /// The checkout this build was made from (`Sources/QuotaBar/Fork/` is
    /// three folders down).
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Fork
        .deletingLastPathComponent() // QuotaBar
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent()

    static var syncScript: URL { repository.appendingPathComponent("Scripts/fork/sync.sh") }

    static func syncCommand(beta: Bool) -> String {
        "'\(syncScript.path)'" + (beta ? " --beta" : "")
    }

    static var footnote: String {
        L10n.t("Fork build: updated with Scripts/fork/sync.sh.", "Fork 版本：用 Scripts/fork/sync.sh 更新。")
    }

    /// Runs the sync script in Terminal, where its progress and any rebase
    /// conflict can be seen. nil on success, else why not.
    static func openSync(beta: Bool) -> String? {
        guard FileManager.default.isExecutableFile(atPath: syncScript.path) else {
            return L10n.t("Not found: \(syncScript.path)", "找不到：\(syncScript.path)")
        }
        let command = FileManager.default.temporaryDirectory.appendingPathComponent("quotabar-fork-sync.command")
        let script = "#!/bin/zsh -il\n\(syncCommand(beta: beta))\n"
        do {
            try Data(script.utf8).write(to: command, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
        } catch {
            return error.localizedDescription
        }
        return NSWorkspace.shared.open(command) ? nil : L10n.t("Could not open Terminal.", "无法打开终端。")
    }
}

/// In the update card, instead of Install and Relaunch.
struct ForkUpdateNotice: View {
    @ObservedObject var store: UsageStore
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.space2) {
            Text(L10n.t(
                "This is a fork build. Bring it up to this release by rebasing and rebuilding it:",
                "这是 fork 版本，请变基并重新构建到这个版本："))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Text(ForkBuild.syncCommand(beta: store.experience.betaUpdates))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                Spacer()
                Button(L10n.t("Update fork", "更新 fork")) {
                    notice = ForkBuild.openSync(beta: store.experience.betaUpdates)
                }
                .glassAction(prominent: true)
            }
            if let notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
