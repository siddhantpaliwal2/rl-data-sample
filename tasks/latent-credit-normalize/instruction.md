<uploaded_files>/app</uploaded_files>

# Data-integrity audit memo: parsed credit reports vs. source PDFs

**Scope:** quarterly sample audit, 40 borrower files. For each file we compared
the tradelines, inquiries and bureau sections produced by the credit-report PDF
parser against a human reading of the same source PDF.
**Result:** 34 of 40 files reconcile exactly. The remaining six show the
discrepancy classes below. Every discrepancy reproduces on re-parse, so none of
this is OCR noise or a transient.

## Findings

**A.** A row whose creditor is one of the recognised filler tokens survives
into the report as if it were a real account - but only when the token's
letter-case differs from its usual form. The usual form is still filtered
correctly, so the screen exists; it just doesn't catch every spelling the
bureaus emit.

**B.** The same account appears twice. Two rows that are genuinely one
tradeline - same account, creditor spelled with different capitalisation - are
both kept, inflating the account count. Exact-duplicate rows do collapse
correctly.

**C.** A genuine creditor line vanishes because it merely *begins* the way a
different kind of line begins. Lines of the other kind are rightly discarded;
the discard is grabbing real creditor lines along with them.

**D.** A tradeline tagged for a bureau lands in no bureau section at all. The
tag is one of the accepted spelling variants of that bureau's abbreviation;
the other variants we sampled attribute correctly, and untagged rows still
broadcast to all scored bureaus as designed.

## Note for engineering

The affected stage is the deterministic line-classification and text
normalization logic under `loangen-agent/agent/documents/credit_pdf/` - the
creditor-line, bureau-tag and address/contact helpers in `normalize.py`, and
the artifact-rejection and de-duplication helpers in `junk_filter.py`. Same
PDF in, same rows out, so each finding above replays from a single line of
input. The existing test suite is green and none of these cases move it, which
is presumably how they shipped. Fix the classification so the findings above
reconcile, without disturbing any file that already parses correctly.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
