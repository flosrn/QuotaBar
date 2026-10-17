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

/// A row of the strip: a provider's own ring (its card's account), or one of
/// its other accounts. `separatorAfter`: the last row of a group.
struct DockSlot: Identifiable, Hashable {
    enum Kind: Hashable {
        case provider(ProviderID)
        case account(String)
    }

    let kind: Kind
    var separatorAfter = false

    /// A provider's row keeps the id upstream's rows had (its raw value), so
    /// `scrollTo` for a reset still finds it.
    var id: String {
        switch kind {
        case let .provider(id): id.rawValue
        case let .account(key): "account|\(key)"
        }
    }

    var provider: ProviderID? {
        if case let .provider(id) = kind { id } else { nil }
    }

    var accountKey: String? {
        if case let .account(key) = kind { key } else { nil }
    }
}

/// The addresses whose accounts sit at the top of the dock, whichever
/// provider they belong to. Kept in this Mac's defaults, not in the source.
enum ForkDockTop {
    static let defaultsKey = "forkDockTopAccounts"

    static var emails: [String] {
        get { UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static func contains(_ email: String?) -> Bool {
        guard let email, !email.isEmpty else { return false }
        return emails.contains { $0.caseInsensitiveCompare(email) == .orderedSame }
    }

    static func toggle(_ email: String) {
        if contains(email) {
            emails.removeAll { $0.caseInsensitiveCompare(email) == .orderedSame }
        } else {
            emails.append(email)
        }
    }
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

    /// The address of the account `id`'s card reads.
    func dockCardEmail(_ id: ProviderID) -> String? {
        switch id {
        case .claude:
            return claudeSignIns.card?.email ?? displayPhase(for: .claude)?.snapshot?.account
        case .codex:
            if let card = codexCardAccount, let email = codexAccounts.saved.first(where: { $0.id == card })?.email {
                return email
            }
            return displayPhase(for: .codex)?.snapshot?.account
        default:
            return nil
        }
    }

    /// The strip's rows, top to bottom: the accounts kept at the top
    /// (`ForkDockTop`), then each provider with other accounts as a group of
    /// its own, then the providers with one ring each, in the dock's order.
    /// Groups end with a separator; rows keep one height, so placing a card
    /// beside a ring stays a matter of its index.
    var dockLayout: [DockSlot] {
        var top: [DockSlot.Kind] = []
        var groups: [[DockSlot.Kind]] = []
        var singles: [DockSlot.Kind] = []
        for id in dockProviders {
            let extras = dockAccounts(after: id)
            var group: [DockSlot.Kind] = []
            if ForkDockTop.contains(dockCardEmail(id)) { top.append(.provider(id)) } else { group.append(.provider(id)) }
            for account in extras {
                if ForkDockTop.contains(account.email) { top.append(.account(account.id)) } else { group.append(.account(account.id)) }
            }
            if extras.isEmpty {
                singles += group
            } else {
                if !singles.isEmpty { groups.append(singles); singles = [] }
                if !group.isEmpty { groups.append(group) }
            }
        }
        if !singles.isEmpty { groups.append(singles) }
        let all = ([top] + groups).filter { !$0.isEmpty }
        var slots: [DockSlot] = []
        for (index, group) in all.enumerated() {
            for (row, kind) in group.enumerated() {
                slots.append(DockSlot(kind: kind, separatorAfter: row == group.count - 1 && index < all.count - 1))
            }
        }
        return slots
    }

    var dockSlotCount: Int { dockLayout.count }

    func dockSlotIndex(of id: ProviderID) -> Int? { dockLayout.firstIndex { $0.provider == id } }

    func dockSlotIndex(ofAccount key: String) -> Int? { dockLayout.firstIndex { $0.accountKey == key } }

    func dockSlot(of id: ProviderID) -> DockSlot? { dockLayout.first { $0.provider == id } }

    /// The extra room the group gaps above row `index` take: what the
    /// coordinator adds to `index × cellHeight` to find that ring.
    func dockGroupOffset(before index: Int) -> CGFloat {
        CGFloat(dockLayout.prefix(index).filter(\.separatorAfter).count) * DockGroupSeparator.extraGap
    }

    /// The extra height of the whole strip for its group gaps.
    var dockGroupsHeight: CGFloat { dockGroupOffset(before: dockSlotCount) }

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

/// An account's ring, for an `.account` row of `dockLayout`.
struct DockAccountRing: View {
    @ObservedObject var store: UsageStore
    let slot: DockSlot
    let hoveredKey: String?
    let onHover: (String, HoverPhase) -> Void
    let onTap: (String) -> Void

    var body: some View {
        if let key = slot.accountKey, let account = store.dockAccount(key) {
            ProviderRing(
                id: account.provider,
                percent: store.dockHeadlinePercent(account),
                mode: store.meterMode,
                showsLabel: false,
                selected: false,
                hovered: hoveredKey == account.id,
                selectionDot: true)
                .overlay(alignment: .bottom) { DockGroupSeparator(shown: slot.separatorAfter) }
                .padding(.bottom, slot.separatorAfter ? DockGroupSeparator.extraGap : 0)
                .onContinuousHover { onHover(account.id, $0) }
                .onTapGesture { onTap(account.id) }
                .contextMenu {
                    Button(L10n.t("Refresh \(account.provider.displayName)", "刷新 \(account.provider.displayName)")) { store.refresh(account.provider) }
                    Divider()
                    DockTopMenuItem(store: store, email: account.email)
                }
        }
    }
}

/// The rule between two groups of rings, in a gap `extraGap` wider than the
/// one between rings of a group, so the groups read as groups before the
/// rule is even seen. Drawn over the gap, not in the stack.
///
/// Placed by the discs, not by the cells: a cell is the disc and, under it,
/// the row kept for the selection dot, empty on every ring but one. Centred
/// on the cell's gap, the rule sat twice as far from the disc above as from
/// the disc below. Its ends fade, as the strip's own ends do when it scrolls.
struct DockGroupSeparator: View {
    let shown: Bool

    static let length: CGFloat = 24
    static let thickness: CGFloat = 1
    static let extraGap: CGFloat = Design.space2

    /// From the cell's bottom to the middle of the empty space between this
    /// disc and the next: the disc ends `dotRow` above the cell's bottom, the
    /// next disc starts `Design.space3 + extraGap` below it.
    static var gapMiddleBelowCell: CGFloat {
        let dotRow = ProviderRing.markSpacing + ProviderRing.markSize
        return (Design.space3 + extraGap - dotRow) / 2
    }

    var body: some View {
        if shown {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.28), location: 0.5),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.length, height: Self.thickness)
                .offset(y: Self.gapMiddleBelowCell + Self.thickness / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Keep this address's accounts at the top of the dock, or stop.
struct DockTopMenuItem: View {
    @ObservedObject var store: UsageStore
    let email: String?

    var body: some View {
        if let email, !email.isEmpty {
            let on = ForkDockTop.contains(email)
            Button(on
                ? L10n.t("Stop keeping \(email) at the top", "取消置顶 \(email)")
                : L10n.t("Keep \(email) at the top", "置顶 \(email)"))
            {
                ForkDockTop.toggle(email)
                store.objectWillChange.send()
            }
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
