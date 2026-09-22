# Phone Cleanup

An Android storage app for one phone. Flutter, one module, built in the cloud
and installed over the air.

It exists because the phone hit 95% full and the Storage screen answers the
wrong question. Settings tells you that Images are 40 GB. It will not tell you
that 8 of those gigabytes are the same eleven photos saved four times each.

## The position it takes

**No one-tap Clean button.** Nothing is ticked when you open a list, and
nothing is deleted that has not been ticked by hand and then confirmed on a
sheet naming the count, the space and what it costs if the finder is wrong.
A scan that turns up 40 GB still starts at zero.

**No trash folder.** A holding area frees no space, which is the entire reason
you opened the app. Deletes are real and there is no undo. The app says so on
its own Settings screen rather than burying it.

**It says what it cannot do.** No app has been able to clear another app's
cache since Android 11. Every cleaner claiming otherwise is clearing its own
cache or nothing at all. This one measures each app through
`StorageStatsManager`, the same source Settings reads, ranks them, and puts you
one tap from the button that does the clearing. Measurement is the value; the
tap is a hand-off.

**Every finder carries a caution.** "We found 4 GB" is only useful beside "and
here is what you lose if we are wrong about it". Old screenshots are usually
junk and occasionally a booking reference, and the app is the one that has to
say that out loud.

## What it looks for

| Finder | What it is |
|---|---|
| Duplicates | Byte for byte identical files, matched on full content |
| Left behind by uninstalled apps | `Android/media/<package>` for packages that are gone |
| Thumbnails and caches | Previews and scratch files that rebuild themselves |
| Waiting in the bin | `.trashed-` files Android holds for thirty days |
| Installer files | APK and OBB sitting in storage after the install |
| Sent copies | The second copy WhatsApp and Telegram keep of what you sent |
| Large videos | Over a threshold you set |
| Biggest single files | Everything else over a threshold you set |
| Old screenshots | Older than a threshold you set |
| Old downloads | Older than a threshold you set |
| Empty folders | No files at any depth. Frees nothing, tidies a lot |

Duplicate detection is three passes, cheapest first: size, then a 256 KB head
hash, then a full SHA-1 read end to end. The full read is not optional. Two
videos from the same camera share a size and a header often enough that head
matching alone would eventually delete something irreplaceable, and that is
the one bug in this app that cannot be apologised for afterwards.

## The other half

A one-off scanner tells you what is there. Phone Cleanup keeps up to forty
scan snapshots, a few hundred bytes each, so the Storage tab can answer the
question you actually have four months later: **which folders got heavier
since last time.** That is the difference between cleaning up once and not
ending up back at 95%.

## Permissions, and what breaks without each

| Permission | Granted where | Without it |
|---|---|---|
| All files access | Settings, Apps, Special app access, All files access | The scanner sees only its own empty sandbox and every number reads zero |
| Usage access | Settings, Apps, Special app access, Usage access | The Apps tab can see installed package size but not data or cache |
| Install unknown apps | Prompted by the updater | Cannot self-update |

Both of the first two are separate grants on separate screens, and neither
appears in the normal permission list. The app links straight to each one.

`Android/data` and `Android/obb` cannot be read by any app, All files access or
not. The scan records them as unreadable and the Apps tab measures what is
inside them through a different API instead.

## Building

There is no Flutter SDK and no Android SDK on the machine this was written on.
Everything is built by GitHub Actions and installed from the release it
publishes, which also means **CI is the first compiler this code ever meets**.

`test.yml` runs `flutter analyze` and `flutter test` on every push, so the
finders and the byte formatting are checked without a phone in the loop. The
finders are pure functions over a list of records with the hash injected,
which is what makes that possible.

Signing is optional but wanted. Set `KEYSTORE_BASE64`, `STORE_PASSWORD`,
`KEY_ALIAS` and `KEY_PASSWORD` as repo secrets and the release APK is signed
with a stable key, which is what lets it upgrade in place. Without them the
build still produces an APK, signed with the debug key, which will not upgrade
an existing install.

> Never lose the keystore. It is gitignored. Without the same key you cannot
> push updates to an installed copy, it would have to be uninstalled first.

## Updating

```
 edit code  ──►  .\publish.ps1  ──►  tag pushed  ──►  GitHub Actions
                                                           │ builds signed APK
                                                           ▼
   phone: a line at the top of Storage  ◄──────────  GitHub Release
```

The app checks GitHub once, quietly, on launch. If a release is newer than
what is installed, a line appears at the top of the Storage tab and one tap
downloads and installs it. Settings has the full control for a manual check.

First install: download the APK from Releases and open it. The first time the
app self-updates, Android asks to allow "install unknown apps". Allow it once
and every update after that is one tap.

## Layout

| Path | What |
|---|---|
| `lib/theme.dart` | Colours, type, and **the one place system bar insets are handled** |
| `lib/scan.dart` | The isolate that walks storage |
| `lib/finders.dart` | The rules. Pure, injected hash, fully tested |
| `lib/models.dart` | Plain data shared across the isolate boundary |
| `lib/selection.dart` | The only code in the app that deletes anything |
| `lib/history.dart` | Scan snapshots and growth between them |
| `android/.../MainActivity.kt` | Volume, per-app sizes, settings hand-offs. Deletes nothing |

### On the bottom inset

The app draws edge to edge, so the gesture bar sits on top of the Flutter
surface and anything laid out to the raw bottom of the window is underneath it
and cannot be tapped.

Nothing in this app reads `MediaQuery` for bottom padding at the call site.
Every screen is built through `AppScaffold` or `TabPage`, every sheet through
`showAppSheet`, and the shell's nav bar carries the system bar's height inside
its own padding. The reserved space is a real widget in a `Column`, not an
overlay, so a new screen cannot forget to account for it: there is no code
path that reaches the bottom of the window at all.

## State

v0.1.0 is built, signed and published. Analyze, tests and the APK build are all
green, and the release APK carries the persistent key, so it upgrades in place.

It has not been run on a phone yet. Everything above is checked by a compiler
and by unit tests over synthetic file lists; none of it has met a real
filesystem. The first scan on the phone is the real test, and the questions it
answers are listed in ROADMAP.md.
