import SwiftUI
import QuotaCore

// FORK(flosrn): one dock ring per account. Everything lives here so an
// upstream merge only meets the few `FORK(flosrn)` call sites in
// EdgeDock.swift. See FORK.md.

/// A Claude sign-in or a kept Codex account other than the one its
/// provider's card reads, drawn as its own ring right after that card's ring.
/// Read from the side models that already read every account on the card's
/// beat (`ClaudeSignInsModel`, `CodexAccountsModel`); nothing extra is fetched.
struct DockAccount: Identifiable {
    let provider: ProviderID
    /// The Claude keychain item, or the Codex account id.
    let key: String
    let email: String?
    let snapshot: UsageSnapshot?
    let error: String?

    var id: String { "\(provider.rawValue)|\(key)" }
}

/// A row of the strip: a provider's own ring, or one of its other accounts.
enum DockSlot: Hashable {
    case provider(ProviderID)
    case account(String)
}

extension UsageStore {
    /// The accounts drawn after `id`'s ring: everything but the card's own.
    func dockAccounts(after id: ProviderID) -> [DockAccount] {
        switch id {
        case .claude:
            // Already without the card's sign-in, hidden ones and duplicates.
            return claudeSignIns.others.map { reading in
                DockAccount(
                    provider: .claude,
                    key: reading.id,
                    email: reading.identity?.email ?? claudeSignIns.identities[reading.id]?.email,
                    snapshot: reading.snapshot,
                    error: reading.error)
            }
        case .codex:
            let card = codexCardAccount
            return codexAccounts.saved.filter { $0.id != card }.map { account in
                let reading = codexAccounts.readings[account.id]
                // The CLI's own account is not among the others the model
                // reads; while the card is pinned elsewhere, its last turn on
                // the card stands in.
                let fallback = account.id == codexAccounts.activeID ? accountReadings["codex|cli"] : nil
                return DockAccount(
                    provider: .codex,
                    key: account.id,
                    email: account.email,
                    snapshot: reading?.snapshot ?? fallback,
                    error: reading?.error)
            }
        default:
            return []
        }
    }

    var dockSlots: [DockSlot] {
        dockProviders.flatMap { id in
            [DockSlot.provider(id)] + dockAccounts(after: id).map { DockSlot.account($0.id) }
        }
    }

    var dockSlotCount: Int { dockSlots.count }

    func dockSlotIndex(of id: ProviderID) -> Int? { dockSlots.firstIndex(of: .provider(id)) }

    func dockSlotIndex(ofAccount key: String) -> Int? { dockSlots.firstIndex(of: .account(key)) }

    func dockAccount(_ key: String) -> DockAccount? {
        for id in dockProviders {
            if let account = dockAccounts(after: id).first(where: { $0.id == key }) { return account }
        }
        return nil
    }

    /// The figure an account's ring shows: the same window the provider's
    /// ring follows in the dock.
    func dockHeadlinePercent(_ account: DockAccount) -> Double? {
        account.snapshot?.headlinePercent(preferring: pickedHeadlineWindow(for: account.provider, on: .dock))
    }

    func dockAccountLabel(_ account: DockAccount) -> String {
        guard !isPrivacyMasked, let email = account.email, !email.isEmpty else {
            return L10n.t("Other account", "其他账号")
        }
        return email
    }
}

/// The rings of `provider`'s other accounts, placed by EdgeDockView right
/// after the provider's own ring. Observes the side models itself: the dock
/// view only observes the store.
struct DockAccountRings: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var claude: ClaudeSignInsModel
    @ObservedObject var codex: CodexAccountsModel
    let provider: ProviderID
    let hoveredKey: String?
    let onHover: (String, HoverPhase) -> Void
    let onTap: (String) -> Void

    var body: some View {
        ForEach(store.dockAccounts(after: provider)) { account in
            ProviderRing(
                id: provider,
                percent: store.dockHeadlinePercent(account),
                mode: store.meterMode,
                showsLabel: false,
                selected: false,
                hovered: hoveredKey == account.id,
                selectionDot: true)
                .onContinuousHover { onHover(account.id, $0) }
                .onTapGesture { onTap(account.id) }
        }
    }
}

/// The card beside an account's ring: its plan, address and windows.
struct DockAccountCallout: View {
    @ObservedObject var store: UsageStore
    let account: DockAccount

    var body: some View {
        VStack(alignment: .leading, spacing: Design.space3) {
            header
            content
        }
        .padding(Design.space3)
        .frame(width: EdgeDockCoordinator.calloutWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.radiusCard + 2, style: .continuous)
                .fill(Color.black))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Design.space2) {
                ProviderGlyph(id: account.provider, size: 15, tint: .white)
                Text(account.provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let plan = account.snapshot?.chipLabels.first {
                    Text(plan.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Spacer(minLength: 0)
            }
            Text(store.dockAccountLabel(account))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = account.snapshot {
            VStack(alignment: .leading, spacing: Design.space3) {
                if let error = account.error {
                    StaleReadingNote(reason: error, fetchedAt: snapshot.fetchedAt)
                }
                let represented = snapshot.balance?.representedWindowIDs ?? []
                let windows = snapshot.windows.filter { !represented.contains($0.id) }
                if windows.isEmpty {
                    Text(L10n.t("No quota windows reported.", "服务商未返回额度窗口。"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                ForEach(windows) { window in
                    QuotaRowView(store: store, id: account.provider, window: window, allowsPick: false, place: .dock)
                }
                Text(L10n.t(
                    "Updated \(QuotaFormat.age(of: snapshot.fetchedAt))",
                    "更新于 \(QuotaFormat.age(of: snapshot.fetchedAt))"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        } else if let error = account.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(Color(hex: "FF9F0A"))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(L10n.t("Loading…", "加载中…"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
