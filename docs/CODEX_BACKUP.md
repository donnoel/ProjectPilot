# Encrypted Codex recovery backups

ProjectPilot creates an AES-256 encrypted baseline of important local Codex data,
then small encrypted delta disk images containing only changed files and deletion
metadata. This supplements the Development mirror and existing readable skills
copies; it does not encrypt the entire Development folder.

## Enable the backup

1. Open ProjectPilot's **Backup** tab and choose **Set up encrypted backup**.
2. Choose a unique password of at least 16 characters. Save it in a password
   manager you can open on a replacement Mac, or another independent safe place.
3. Confirm the password and acknowledge that you saved it, then enable the backup.

ProjectPilot stores a local, device-only Keychain item for automatic backups. The
password is not written to UserDefaults, Git, process arguments, recovery images,
or the cloud folder. The app cannot recover a forgotten password. The password
must survive loss of the original Mac independently of its local Keychain.

The first baseline starts after any current Development backup finishes. Later
automatic backups run at most hourly while ProjectPilot is running and add only
files whose size, modification time, type, or symlink target changed. **Back up
Codex now** checks immediately but creates no image when nothing changed. The
existing **Back up now** also attempts a Codex update before the Development
mirror. Failures wait 15 minutes before an automatic retry. The two backup
operations do not run concurrently.

## Locations and recovery window

- Encrypted local copies: `~/Development/CodexBackups/`.
- Cloud destination: iCloud Drive → `Development/CodexBackups/`.
- Private temporary staging: `~/Library/Application Support/ProjectPilot/CodexBackupStaging/`.

Each encrypted artifact has a unique `Codex-<UTC timestamp>-<UUID>.dmg` name.
`Chain.json` lists the required baseline and deltas in restore order. `Latest.json`
records the last artifact's timestamp and ciphertext SHA-256, and `RESTORE.md`
accompanies the chain. Only ciphertext and these non-secret instructions and
summary metadata enter Development or iCloud. The private per-file manifest stays
under `~/Library/Application Support/ProjectPilot` with mode 0600 permissions.
Private staging is removed after success or failure; a later run removes this
service's abandoned UUID staging directories under an exclusive process lock.

A new full baseline compacts the chain after 30 days or 120 deltas. The previous
chain is removed only after the replacement baseline is encrypted, verified, and
copied successfully. Migrating from the original full-snapshot format adopts the
newest verified image as the baseline and removes redundant older images only after
the first incremental publication succeeds. Backups need temporary space only for
changed files, database snapshots, and the compressed delta during normal runs.

## Included and excluded data

Included:

- Global `AGENTS.md`, `config.toml`, local app/project state, history and session index.
- Sessions, archived sessions, memories and memory databases.
- Automation definitions and their non-generated files, rules, and both skill libraries.
- Attachments, generated images, visualizations, and dictation history.
- Local SQLite state databases and worktree source files, including unpublished files.

Excluded:

- `auth.json`, browser sign-ins, logs, caches, downloaded plugins, and old Codex backups.
- Lock/socket files and database WAL/SHM sidecars.
- Generated dependencies/build folders inside automations and worktrees, and
  worktree `.git` directories (worktree `.git` pointer files are retained).

Other application secrets and settings, OS Keychain recovery, and files outside
these selected roots need their own recovery plan. Symlinks inside the snapshot
are preserved rather than followed; restore their external targets separately.
A symlink replacing a selected source root or backup destination stops the backup
for review rather than silently copying another location.

## Database consistency and verification

SQLite uses its read-only online backup API into a new private file, including
committed WAL contents. Each destination passes `PRAGMA quick_check`. A read
transaction fixes the source view while WAL writers continue. A busy, corrupt,
or inaccessible database fails the new snapshot without rotating old archives.
Separate databases and other files are captured over a time window, not as a
single atomic snapshot of every Codex component.

The disk image is checked for encryption and its internal checksum is verified
with the password. The encrypted cloud-folder copy must match the ciphertext
SHA-256 before its receipt is published and old snapshots are rotated.

**Verified in the local iCloud folder does not prove Apple's upload completed.**
Before erasing the original Mac, confirm iCloud finished synchronization and that
you can download and unlock a complete image from another device. System Health
reports an unconfigured, failed, or stale Codex backup as needing attention.

## Restore on a replacement Mac

1. Download every image listed in `Chain.json` plus `RESTORE.md` from iCloud. Keep
   an untouched copy. Mount the first image with the separately saved password.
2. Install Codex, then quit it and all Codex CLI/background sessions before copying
   data. Preserve any newer `~/.codex` folder rather than merging live databases.
3. Copy **CodexHome** and **AgentSkills** from the first image into a separate
   recovery folder. Mount each remaining image in `Chain.json` order. For every
   delta, apply the encrypted `Delta.json` deletion list inside that recovery folder,
   then overlay its CodexHome and AgentSkills contents. Never edit mounted images.
4. After all deltas are applied, move the recovered CodexHome to `~/.codex` and
   AgentSkills to `~/.agents/skills`. Finder's **Command-Shift-.** shows hidden files.
5. Restore Development repositories too. Worktree `.git` pointers can contain old
   absolute paths: recover changed source files first, then reconnect/recreate the
   worktrees deliberately. Do not assume their Git links are already usable.
6. Reopen Codex, sign in again, reinstall plugins, and verify familiar conversations,
   memories, settings, skills, and automation definitions. Review schedules before
   enabling tasks. Restoring files is not proof that every app feature works.
7. Set up ProjectPilot's encrypted backup with the same saved password. Existing
   images are verified before storing a replacement local Keychain item.

The archive's own `RESTORE.md` is self-contained so recovery does not require this
repository or a working ProjectPilot installation. Never put the password next to
the archives or into a Git repository.

Implementation references: [SQLite online backup API](https://sqlite.org/backup.html)
and Apple's built-in `hdiutil` manual for AES-256 disk images and private stdin input.
