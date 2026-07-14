<uploaded_files>/app</uploaded_files>

A handful of the meeting-notes app's pure helper functions return wrong results
for certain inputs, even though the app looks correct for the ordinary inputs it
was built against. The bad outputs cluster at the **edges** of each helper's
input range — a value sitting
exactly on a limit, the wrong side of a cutoff, a comparison that should be
case-insensitive but isn't, a count that runs one past its cap, an input landing
at the very start of a range instead of inside it. Comfortable mid-range inputs
are handled correctly, which is why the behaviour looked fine in normal use and
in the values the code was originally exercised with.

The affected code is the deterministic, side-effect-free utility layer:

- `frontend/src/lib/format.ts` — the display formatters that turn a recording's
  raw duration and file size into the short strings shown in the UI.
- `backend/src/services/search.services.ts` — the keyword side of the recording
  search (which stored recordings match a typed query, how many come back, and
  the snippet of surrounding text shown for each hit).

Reported symptoms, from user-facing behaviour:

- A recording that runs right up to a whole hour is shown with an over-large
  minutes value instead of rolling up into the hour-and-minutes form the app
  uses for longer recordings; shorter recordings look fine.
- Larger (megabyte-scale) file sizes are shown with a different amount of
  precision than the kilobyte-scale sizes right below them, so the size column
  looks inconsistent as it crosses into megabytes.
- Searching for a term that a recording clearly contains sometimes finds
  nothing, when the stored title or transcript uses different capitalisation
  from what was typed; matching the same letters in the same case still works.
- A search occasionally returns more results than the number the caller asked
  for.
- When the searched term happens to fall at the very beginning of a recording's
  transcript, the preview snippet shown for that hit is a different length from
  the snippet shown when the term appears later in the transcript.

This is pure, deterministic logic — string/number formatting and in-memory
keyword matching, with no I/O on these paths. In each case a correct sibling
right next to the mistake (a neighbouring unit cutoff, the matching branch on
the other search mode, the already-lowercased query, or the function's own
fallback) shows what the intended behaviour is. Correct the boundary handling so
these edge inputs produce the right results, without changing behaviour anywhere
the helpers are already right. Keep the fix in the library source, not in any
test.
