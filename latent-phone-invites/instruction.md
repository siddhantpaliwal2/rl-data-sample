<uploaded_files>/app</uploaded_files>

The CRM contact tools occasionally store or resolve the wrong value for phone
numbers and loan-type selections that arrive in less common — but still
legitimate — shapes, even though the whole test suite is green. The mistakes
cluster around **unusual input formats and ambiguous edge cases**: a phone
number written in a dialing format the everyday cases never use, a number whose
correct country is ambiguous unless the configured default region is honored,
or a loan-type string whose casing or vintage differs from the typical
examples. On ordinary inputs the tools are correct, which is why the existing
tests (they feed clean, typical values) never surface the problem.

The affected code is the deterministic normalization and lookup logic under
`loangen-agent/agent/integrations/cartesia/phone.py` — the E.164 phone
normalization, region fallback and formatting helpers — and
`loangen-agent/agent/services/smbcontacts/loan_types.py` — the loan-type alias
and label resolution. This is pure, side-effect-free string and table logic;
the bugs are in how the uncommon inputs and the boundaries between cases are
handled, not in any I/O or state.

Correct the handling so these functions are right on the unusual and boundary
inputs, without changing behavior anywhere the current tests already pin. The
repository's existing tests all pass and must stay passing; correctness on the
edge inputs is the bar.

Do not modify anything under `loangen-agent/tests/`.

Verify with:

    cd /app/loangen-agent && python -m pytest tests -v
