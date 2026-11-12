# Small encrypted Codex recovery kits

ProjectPilot backs up the essentials needed to rebuild Don's Codex working setup.
Each AES-256 disk image is a complete, independent recovery kit. Full chat history
is deliberately excluded. This supplements the normal Development mirror and
readable skills backup; it does not encrypt or replace them.

## Schedule, retention and size limits

- Automatic backups run at most daily while ProjectPilot is running. A version-1
  or version-2 legacy receipt triggers migration immediately, even when recent.
- **Back up Codex now** creates a fresh kit immediately. **Back up now** also
  attempts the kit before the normal Development mirror. The writers serialize.
- Retain at most one kit per UTC day for seven distinct days, plus two older
  weekly copies, subject to a 2 GiB budget per destination. Newest copies win;
  the budget can shorten the recovery window. Each retained kit stands alone.
- The source budget is 1 GiB and the encrypted-image limit is 512 MiB. Exceeding
  either fails visibly and preserves the previous backup; files are not silently
  omitted to meet a limit. Review large worktree/skill files before retrying.
- Failed automatic attempts retry after 15 minutes. Health warns after 48 hours
  without a recorded verified kit or immediately on a reported backup error.

## What is protected

Included:

- Global `AGENTS.md`, optional `AGENTS.override.md`, `config.toml`, and local
  project preferences in `.codex-global-state.json`.
- Both skill libraries, rules, text memories and memory databases.
- `automation.toml` definitions; schedules must be reviewed before re-enabling.
- Non-generated source under `.codex/worktrees`, including unpublished files.
  Files must still be recovered into their repositories; Git pointer paths may
  be stale on another Mac.

Excluded:

- Sessions, archived sessions, the large thread-history database, other runtime
  databases, transcript/history indexes, attachments, generated images,
  visualizations and dictation recordings/history.
- Automation run artifacts, evidence folders, logs and caches.
- `auth.json`, browser sign-ins, downloaded plug-ins and previous backups.
- Generated worktree dependencies/builds, lock files, database WAL/SHM sidecars
  and worktree `.git` directories. Worktree `.git` pointer files are retained.

This is a setup-and-source recovery kit, not a full conversation-history backup.
Saving decisions and important results in the Documentation library remains useful.
Normal Development files and application credentials outside these roots require
separate recovery. Symlinks are preserved as links; external targets are not copied.

## Password and destinations

Set up a unique password of at least 16 characters in ProjectPilot's Backup tab,
acknowledge saving it in an independent password manager, and keep that recovery
password accessible after losing this Mac. Existing installations reuse their
saved password. Never send it through chat or put it beside the images.

The automatic password copy is stored only in the local device-only Keychain.
It is never placed in process arguments, UserDefaults, logs, Git, recovery files,
or the iCloud destination. Encryption failure has no plaintext fallback.

- Local: `~/Development/CodexBackups/`.
- Cloud folder: iCloud Drive > `Development/CodexBackups/`.
- Private staging: `~/Library/Application Support/ProjectPilot/CodexBackupStaging/`.

`RecoveryKits.json` lists independent version-3 receipts. `Latest.json` records the
newest kit's timestamp, ciphertext SHA-256, file/database counts, encrypted size
and restore-check time. Metadata contains no source-file manifest or password.
The per-file SHA-256 manifest is inside the encrypted image. `RESTORE.md` accompanies
the images and is also inside each kit. Plaintext staging is private and removed
on completion or failure under the exclusive backup lock.

## Verification and migration safety

1. Snapshot selected SQLite databases using the read-only online backup API;
   include committed WAL data and require `PRAGMA quick_check` to pass.
2. Encrypt the kit with AES-256 and verify the disk-image encryption/checksum.
3. Copy ciphertext to the iCloud folder and compare its SHA-256.
4. Unlock that cloud-folder image read-only using the password over private stdin.
5. Copy its recovery roots to private temporary storage and compare every restored
   file, directory and symlink with the original encrypted manifest.
6. Detach the image and publish both new receipts and the independent-kit index.
7. Only then prune expired kits and retire owned legacy baseline/delta images,
   `Chain.json`, and the obsolete private incremental state.

A preparation, encryption, copy or restore-check failure preserves the old chain.
Nothing is restored into the live `.codex` folder during verification. Separate
source files/databases are captured across a time window, not atomically as a
whole app. This rehearsal proves the copied kit can be decrypted and restored;
it does not prove every Codex feature works on a replacement Mac.

**Local iCloud-folder verification is not proof of server upload.** Before erasing
this Mac, verify sync completed and download/unlock a kit from another device.

## Restore

1. Download one listed kit and keep an untouched copy. Mount it with the separately
   saved recovery password. No other kit or legacy chain is required.
2. Copy `CodexHome` and `AgentSkills` into a separate recovery folder. Keep the
   mounted image unchanged. `RecoveryManifest.json` contains the encrypted hashes.
3. Install Codex, quit it and every CLI/background session, and preserve the fresh
   data separately. Recover the selected files into `~/.codex` and skills into
   `~/.agents/skills`. Review configuration paths, links and schedules first.
4. Restore Development repositories through their normal backup/Git process.
   Recover unpublished worktree source before deliberately recreating Git links.
5. Sign in again, reinstall plug-ins, check instructions/skills/memories/source,
   and re-enable only the tasks you still want. Full old conversations are not
   part of this recovery. Reconfigure ProjectPilot using the saved password.

The image's `RESTORE.md` is self-contained. Implementation references:
[SQLite backup API](https://sqlite.org/backup.html) and the installed `hdiutil` manual.

## Observed verification - November 12, 2026

Signed build 7 was installed and launched on Don's Mac with its existing signing
identity and entitlements preserved. All 14 focused backup tests passed, including
wrong-password/manifest rejection, independent restores, daily scheduling, size
limits, retention and preservation of the legacy chain on failure. The signed
build passed with warnings treated as errors.

The real-data run produced one 215,537,664-byte encrypted recovery kit containing
5,751 files and two memory-database snapshots. Its iCloud-folder copy was decrypted
and restored into private temporary storage, and all restored entries matched the
encrypted manifest before receipts were published. Independent post-run checks
confirmed matching ciphertext SHA-256 and receipts in both locations, no remaining
legacy chain images/index/state, and no abandoned plaintext staging. The nine-image
legacy chain had totaled 20.307 GB per destination; the replacement is about 216 MB.

This is a real local restore rehearsal, not a replacement-Mac or server-download
test. iCloud server upload and manual visual acceptance were not independently
verified. The prior build was retained locally for app rollback; conversation
history remains in the live Codex source but is no longer protected by these kits.
