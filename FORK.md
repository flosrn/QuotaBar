# flosrn/QuotaBar — fork notes

A fork of [QuotaBar/QuotaBar](https://github.com/QuotaBar/QuotaBar) kept as a
short stack of commits on the `fork` branch, rebased onto each upstream release.

## What it changes

| Change | Where |
|---|---|
| **One dock ring per account.** Claude's other sign-ins and Codex's other kept accounts each get their own ring, with their own hover card (plan, address, windows). Rows: the accounts kept at the top, then one group per provider with several accounts, then the one-ring providers, a thin rule between groups. Right-click a ring › **Keep … at the top** pins that address's accounts, whatever the provider (defaults key `forkDockTopAccounts` in `bar.quota.QuotaBar`). Nothing extra is fetched: the rings read the side models that already read every account on the card's refresh (Claude's are throttled to one read per 90 s, as upstream). | `Sources/QuotaBar/Fork/DockAccounts.swift`; call sites in `EdgeDock.swift` |
| **The default Claude sign-in is removable.** `Claude Code-credentials` (plain `claude`, no `CLAUDE_CONFIG_DIR`) gets a Remove button like the others; the card then moves to the first sign-in still listed. Claude Code's own login is not touched. | `Sources/QuotaCore/Fork/ClaudeDefaultSignIn.swift`; `AccountProfiles.swift`, `ClaudeSignIns.swift`, `UsageStore+Profiles.swift`, `ClaudeSignInsViews.swift`, `CodexClaudeProviders.swift` (`isConfigured`) |
| **Codex › Add account.** Runs `codex login` in Terminal with a throwaway `CODEX_HOME` (`~/.codex-quotabar-login-*`) and the file credential store, keeps the sign-in in QuotaBar's keychain vault, deletes the folder. Finished folders are swept on every Codex refresh and when Codex's settings open, so a sign-in that took long, or finished after a quit, is still kept; an unfinished folder is removed after a day. `~/.codex/auth.json` (the CLI's account) is never touched. | `Sources/QuotaCore/Fork/CodexAccountLogin.swift`, `Sources/QuotaBar/Fork/CodexAccountAdd.swift`; button and sweep in `CodexAccountsViews.swift`, sweep in `UsageStore.swift`; `keep` made internal in `CodexAccounts.swift` |
| **Updates.** The fork is signed with a local certificate, so upstream's updater could not install an official build (it requires the same team). The fork takes the Homebrew path instead: the update card still announces each release and offers **Update fork**, which runs `Scripts/fork/sync.sh` in Terminal. | `Sources/QuotaBar/Fork/ForkBuild.swift`; `UsageStore.swift`, `UpdateWindow.swift`, `SettingsUpdatesPane.swift` |

Every edit to an upstream file carries a `FORK(flosrn)` comment; everything
else is in a `Fork/` folder or a `Fork*Tests.swift` file, so a rebase conflict
is always next to one of those markers.

```bash
git grep -n 'FORK(flosrn)'
```

## Staying on upstream releases

```bash
Scripts/fork/sync.sh --check   # is there a newer release? (exit 10 if so)
Scripts/fork/sync.sh           # rebase onto the newest stable tag, build, test, package, install
Scripts/fork/sync.sh --beta    # same, pre-releases included
Scripts/fork/sync.sh --rebuild # no rebase: rebuild and reinstall HEAD
```

The app checks for releases every six hours, as upstream does, and the update
card's **Update fork** button runs the same script (with `--beta` when Beta
updates is on in Settings › Updates).

- Before rebasing, the branch is saved as `fork-before-<tag>`; undo with
  `git reset --hard fork-before-<tag>`.
- A conflict stops the script with the rebase in progress: resolve, `git rebase
  --continue`, run the script again. `git rebase --abort` gives up.
- The previous app is kept at `~/Library/Caches/quotabar-fork/QuotaBar.app`.
- `--push` force-pushes (with lease) the branch to `origin`.

Remotes: `upstream` = QuotaBar/QuotaBar, `origin` = flosrn/QuotaBar.

## Signing and the keychain

Packaged with `SIGN_ID="Orca Dev"` (override with `SIGN_ID`). The bundle id
stays `bar.quota.QuotaBar`, so the fork shares upstream's config
(`~/.config/quotabar/config.json`), defaults and keychain items (service
`bar.quota.QuotaBar`, which holds the Codex vault and manual tokens).

- The first launch of a build signed differently from the one that created
  those items asks once per item; choose **Always Allow**. A stable signing
  identity keeps that answer across rebuilds; an ad-hoc signature would not.
- Claude Code's keychain items are read through `/usr/bin/security`, as
  upstream does, so they raise no prompt.
- Run the fork **instead of** the official app, never beside it: both would
  read every provider and renew Claude sign-ins.

## Setting up the accounts

1. **Claude**: Settings › Providers › Claude › Accounts. Remove
   `… (default)` if it should not be read; **Add account** for each account
   (Terminal opens `claude auth login` in its own config dir). Each account
   then has its own dock ring.
2. **Codex**: Settings › Providers › Codex › Accounts › **Add account** for each
   account not yet kept; sign in in the browser that opens. The CLI's own
   account is the Codex card; every kept one besides it gets a ring.
