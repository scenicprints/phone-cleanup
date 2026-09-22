# Roadmap

Written before the first build, so treat everything below the line as
provisional until the app has actually run on the phone once.

## Before anything else

1. **Get it to compile.** There is no Flutter SDK on the machine this was
   written on, so the first CI run is the first syntax check. Expect a few
   rounds.
2. **Create the repo and the signing key.** `scenicprints/phone-cleanup`,
   public, plus a keystore in a sibling `phone-cleanup-signing` folder and the
   four base64 secrets. Without the key the first APK cannot be upgraded in
   place and has to be uninstalled before the second one goes on.
3. **One real scan on the phone**, with a stopwatch. The unknowns are how long
   a full walk takes at 95% full, and whether the duplicate pass reads enough
   to be annoying. If the walk is slow the fix is to report progress more
   often, not to walk less.

## Likely first fixes

- **Duplicate pass cost.** Full SHA-1 of everything that survives size and
  head matching is correct but potentially minutes on a phone holding a lot of
  identical video. If it is bad, the fix is to hash in parallel across a few
  isolates, not to weaken the match.
- **Memory on the walk.** `kMaxFiles` is set at 800,000 with no evidence
  behind it. One real scan says whether that is generous or optimistic.
- **`Download/` matching.** Matched as a path substring, so a folder called
  `Downloaded Maps` is caught too. Wants anchoring to the real top-level
  folder once there is a phone to test against.

## Worth doing next

- **Photo similarity, not just equality.** Exact duplicates are the safe
  case. The real weight on a camera phone is burst shots: eight frames of the
  same moment, one of them worth keeping. That needs a perceptual hash and a
  side-by-side picker, and it must never auto-pick.
- **Thumbnails in the lists.** Deciding whether to delete a 400 MB video by
  reading its filename is not really deciding. Rows for images and video
  should show a frame.
- **Open a file before deleting it.** A row should be able to hand the file to
  whatever app normally opens it, so "what even is this" has an answer that is
  not a guess.
- **Per-folder growth in the Storage tab.** Snapshots already carry the top 25
  folders. The comparison only runs against the immediately previous scan; it
  could run against any two.
- **A size column that sorts.** The folder browser is biggest-first always.
  Sometimes the question is oldest-first.

## Deliberately not doing

- **A one-tap Clean button.** The whole position of the app is that it
  proposes and you dispose. A button that deletes without a list is the thing
  every bad cleaner does.
- **A trash folder.** It frees no space. At 95% full that makes it worse than
  useless, it makes it a lie.
- **Scheduled background cleaning.** Nothing should delete a file on this
  phone while nobody is looking at it.
- **Claiming to clear other apps' caches.** Not possible since Android 11.
  The Apps tab measures and hands off, and says why.
