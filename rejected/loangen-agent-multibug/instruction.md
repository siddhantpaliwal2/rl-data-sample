<uploaded_files>/app</uploaded_files>

Single-line defects were introduced across the qualification, product-matching,
document-requirements, extraction, credit-report, contact and invite modules of
`loangen-agent`. Types and signatures are unchanged and the code still runs; only
the computed output is wrong, and each defect surfaces only on specific inputs.
Restore the intended behavior.

You may edit ONLY these files:

- loangen-agent/agent/services/cre_qualification/facts.py
- loangen-agent/agent/services/cre_qualification/required_docs.py
- loangen-agent/agent/services/cre_qualification/lender_match.py
- loangen-agent/agent/services/cre_qualification/recommendation.py
- loangen-agent/agent/documents/credit_pdf/bureau_router.py
- loangen-agent/agent/documents/credit_pdf/junk_filter.py
- loangen-agent/agent/documents/extractors/cre_fields.py
- loangen-agent/agent/services/smbcontacts/loan_types.py
- loangen-agent/agent/services/smbinvites/schemas.py
- loangen-agent/agent/integrations/cartesia/phone.py

Do not modify anything under `loangen-agent/tests/`.

Run the suite from `/app/loangen-agent`:

    cd /app/loangen-agent && python -m pytest tests -v
