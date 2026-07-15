<uploaded_files>/app</uploaded_files>

# DEALDOC-2214: some deal documents lose one field at extraction

**Type:** Bug · **Priority:** High · **Component:** document field extraction
**Reporter:** underwriting operations

## Description

Since the last review cycle we have four confirmed cases where a deal document
was parsed, most fields came out right, but one structured number the document
plainly contains never made it into the extracted fields. Re-uploading
reproduces it every time, and in each case a *nearly identical* document - same
layout, slightly different figures - extracts perfectly. So this is not a
formatting or OCR problem; something about the particular values themselves is
tripping the extraction.

## Cases

1. **An appraisal** whose appraised value comes back empty. The document is
   well-formed and the figure is plainly there; a sister appraisal for a
   somewhat larger property extracts its value fine.

2. **A rent roll** that yields no total rent. It is a small roll - the leanest
   one we've seen come through - but it is a legitimate rent roll, and rolls
   with more rows total correctly.

3. **A settlement statement** whose loan amount comes back empty. It is a
   modest loan, on the small end of what we write, but well within what the
   product allows; larger statements extract normally.

4. **A credit summary** for an exceptionally strong borrower that yields no
   score at all. Weaker borrowers' summaries extract their scores fine. The
   strong score is a real, valid score - the extractor just won't hand it over.

## Acceptance

The extractors are deterministic - same document text in, same fields out.
Whatever is rejecting these particular values must be found and corrected so
each case above yields the number its document states, and nothing that
currently extracts correctly changes. The repository's existing tests all pass
today and must still pass.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
