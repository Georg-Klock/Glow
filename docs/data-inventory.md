# Where the data lives

Every copy of Glow's data, what it holds, and what the OS does with it. This is
the inventory #284 asked for, written down so that "local to the phone" stays a
claim about *files* rather than a mood.

Two facts govern everything below, and neither is negotiable per copy:

- **No code sets a backup or protection attribute.** There is no
  `isExcludedFromBackup`, no `FileProtectionType`, and no
  `com.apple.developer.default-data-protection` entitlement in either target —
  `project.yml` declares App Groups and nothing else. Every file therefore
  carries the platform defaults for wherever it sits, and
  `BackupPolicyTests` fails the suite if any of those APIs appears.
- **The protection class is forced, not chosen.** The widget must read the
  store while the phone is locked — a Home Screen that goes blank at the lock
  screen is a broken widget — and the only class that allows that is
  `completeUntilFirstUserAuthentication`, which is also the platform default.
  "Hardening" any store file past it is not a policy option; it is a widget
  regression wearing a privacy costume.

What that adds up to: **history is phone-only, and Glow makes no recovery
promise** — losing the phone loses the history, and nothing in the app says
otherwise. But not promising recovery is not the same as preventing it. The
OS backup carries whatever the person's own backup choice covers, under keys
the person controls (a password-encrypted local backup, standard iCloud
Backup, or iCloud Backup under Advanced Data Protection), and Glow neither
labels that a feature nor opts out of it. Excluding the store from backup
would convert "no promise" into "guaranteed loss", which is a different and
worse product. See the 2026-08-25 entry in `docs/decisions.md`.

## The copies

Each entry names the path, what is in it, who writes it, its lifetime, and
what the OS defaults mean for it. "Backed up" means eligible for iCloud Backup
and local computer backups under the person's own settings; the protection
class is `completeUntilFirstUserAuthentication` everywhere unless said
otherwise, per the entitlement facts above.

### The active store

`<App Group container>/Glow.store`, plus the `-wal` and `-shm` sidecars
SQLite keeps beside it. The whole record: every habit, every completion.
Written by the app and by the widget's intents (two processes, one file); read
by the widget's providers through a read-only container. Lives for the
install. **Backed up.** The sidecars matter as much as the database — the
recent writes are the ones still in the WAL (#131) — and because nothing sets
per-file attributes, a sidecar SQLite recreates carries the same defaults as
the database it belongs to; there is no per-file write that could drift.

### The app-private fallback

`<app container>/Library/Application Support/Glow.store` plus sidecars. The
same shape as the active store, used only while the App Group container is
unavailable (entitlement missing, profile not caught up). The app keeps
working against it; only the widget goes blank. **Backed up** — Application
Support is inside the backup set.

### The legacy store

`<app container>/Library/Application Support/default.store` plus sidecars.
The store SwiftData wrote before `StoreLocation` existed. After migration it
is **deliberately never deleted** (#131): reclaiming the space is a separate,
later decision. On any install that predates the App Group it is a full,
aging copy of the history as of the migration. **Backed up.**

### Migration staging

`<store directory>/Migration-Staging/Glow.store` plus sidecars. A complete
copy assembled beside the destination so promotion is a rename. Transient by
construction — a `defer` removes the directory on every path out of
`StoreMigration.run`, so it exists only during an attempt, or between a
process death mid-attempt and the next launch's attempt, which deletes and
rebuilds it. Sits in the same container as the destination, so nominally
backup-eligible; in practice its lifetime is too short to matter, and a
restored staging directory is deleted before it is ever read.

### Quarantine

`<store directory>/Quarantine/<UTC stamp>-<uuid>/Glow.store` plus sidecars.
A displaced store, moved aside rather than deleted — whatever is wrong with
it, **it is the only copy of whatever it does contain**, and for a divergent
history a quarantine can be the sole survivor of some completions. Kept
indefinitely. **Backed up**, which is exactly right for the one copy that
exists because deleting it was refused.

### The migration record

`<store directory>/Glow.store.migration.json`. Format version, generation
UUID, timestamps, source file *name*, habit and completion counts, cumulative
day-stamp count, and — after a divergence — `unmergedSource`, an absolute
path into the install's own container. No habit names, no history. Rewritten
in place, atomically. **Backed up.** The absolute path in `unmergedSource` is
install-scoped and goes stale across a restore onto a new container UUID;
that costs a later merge its shortcut, not its data, because the source file
itself travels in the same backup.

### App Group defaults

`<App Group container>/Library/Preferences/group.com.georgklock.glow.plist`.
Settings (`glowPeakHeadroom`, `weekFirstWeekday`, `weekRestDay`, `islandPop`),
the debug today override, widget burst notes, and the widget trace — which
records habit UUIDs, counts and timings and never a name; that claim is
enforced by `WidgetTraceRedactionTests`, not by intent. **Backed up.**

### Standard-defaults fallback

`<app container>/Library/Preferences/com.georgklock.glow.plist`. Where the
same settings land while the App Group is unavailable
(`GlowSettings.store` falls back to `.standard`, exactly as the store file
falls back). **Backed up.**

### Temporary exports

`<app container>/tmp/HistoryExports/Glow Up history <yyyy-MM-dd>.csv` or
`.json`. The full history as plaintext, existing between "Export" being
tapped and the share sheet going away — discarded on dismissal, swept before
the next export, and reclaimable by the OS like anything in `tmp` (#142).
**Not backed up**: `tmp` is outside the OS backup set by location. This is
the one copy whose placement excludes it, and that is the right answer for a
plaintext projection whose lifetime is one share sheet — the record it was
made from is the store, which is covered above.

### Copies Glow does not control

Whatever a person does with an export — Mail, Files, AirDrop — is a
provider-owned copy under that provider's retention and sync rules. The share
sheet is the boundary: past it, the file is the person's to place, which is
the feature.

## What the simulator can and cannot verify

`BackupPolicyTests` holds what is honestly checkable in CI:

- **The absence of the APIs.** A source scan over `Glow/` and `GlowWidget/`
  fails if anything starts setting `isExcludedFromBackup` or a file-protection
  class, and a scan of `project.yml` fails if a `default-data-protection`
  entitlement appears. The policy *is* the defaults, so the enforceable
  invariant is that nothing moves off them silently.
- **That an export carries no exclusion marker** — a resource-value read on a
  file `ExportStore` just wrote, which returns a meaningful answer on the
  simulator.

What only a device can measure, and what has **not** been measured:

- **Effective protection classes.** The simulator's filesystem does not
  implement iOS per-file Data Protection, so reading `NSFileProtectionKey`
  there does not report what a phone would enforce. Whether every file above
  actually carries `completeUntilFirstUserAuthentication` on hardware — and
  whether SQLite-recreated sidecars keep it — is a device measurement.
- **Backup round-trips.** No backup → wipe → restore has been performed, so
  actual App Group restore behaviour, the migration record's post-restore
  state, and quarantine survival across restore are all unmeasured. The
  inventory says what the platform documents, not what a protocol proved.

Neither gap is faked by a test. If either is measured on a device later, the
result belongs here, dated.
