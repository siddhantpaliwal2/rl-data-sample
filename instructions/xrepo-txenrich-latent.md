<uploaded_files>/app</uploaded_files>

# Forum digest: "A few statement rows get the wrong category or payee"

Collected from a user support thread. In every case the money moved correctly;
only the derived label is wrong - the category, the sub-tag, or the counterparty
name - and only on a handful of unusual row shapes. Three representative posts,
lightly anonymized, then a maintainer note.

---

**mango_saver** -
> Two rows on this month's statement look off. A credit whose reference note is
> nothing but a long all-numeric string used to show up as a cheque deposit and
> now it just reads as a generic transfer. Separately, my salary credit - whose
> narration is a bare numeric code and nothing else - has stopped picking up the
> salary sub-tag it always had.

**rk_ontheroad** -
> Mine is the name field, not the category. On transfers whose narration opens
> with a direction word ahead of the name, the counterparty now comes back
> empty or wrong. Ordinary transfers that don't open that way are still
> labelled fine; it's only that leading-keyword narration style.

**auditlens** -
> Bill transfers that use a slash-delimited reference are pulling the wrong
> payee. When the reference is laid out as four fields - a type, a sub-type, a
> numeric reference, then the payee name as the final field - the app is lifting
> the numeric reference into the name column instead of the actual name sitting
> at the end.

---

**Maintainer note.** Consolidating these. Each one sits on an edge form that
everyday rows rarely produce, which is why routine activity looks healthy and
nothing tripped in review. On top of the three above we reproduced one more in
the same family: an offsetting credit that arrives immediately after its
matching debit is being recorded as a bounce rather than the reversal it
really is.

The labeling logic is deterministic - the same row always maps to the same
label - so each complaint can be recreated from a single synthetic row and
chased to the exact rule at fault. Expect the faults to sit on boundaries and
structural offsets inside otherwise-correct rules, not in the common paths.

**Ask for engineering:** restore correct handling so these edge rows label
correctly again, without shifting any row that already comes out right. Success
is that the situations described here enrich correctly and nothing that is
currently correct changes.
