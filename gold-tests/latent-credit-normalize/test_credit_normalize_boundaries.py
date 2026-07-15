"""Boundary / edge correctness for credit-PDF line classification + normalization.

These assert the right verdicts on edge inputs that the credit-PDF pipeline
suite never exercises: a placeholder creditor name arriving in mixed case, two
tradelines that duplicate each other but for the casing of the creditor, a
borrower name that merely begins with a street-suffix token, an Equifax column
tag written with its alternate abbreviation, and a real creditor whose name
starts with a digit. The pipeline-level tests only ever feed values comfortably
away from these edges, so a boundary regression here stays invisible to them.

The uniquely-correct side of each boundary is fixed by the surrounding code: a
placeholder set that is stored lower-case, a sibling dedupe/pool key that is
case-folded, sibling patterns in the same helper that are end-anchored, a bureau
abbreviation table that lists the alternate code, and a character class that
describes a whole line of digits/currency.
"""

from __future__ import annotations

import unittest

from agent.documents.credit_pdf.junk_filter import (
    dedupe_tradelines,
    is_junk_creditor_name,
)
from agent.documents.credit_pdf.models import ParsedTradeline
from agent.documents.credit_pdf.normalize import (
    bureau_tags_from_text,
    is_address_or_contact_line,
    is_plausible_creditor_line,
)


class TestUnknownCreditorCaseFold(unittest.TestCase):
    def test_mixed_case_placeholder_is_junk(self) -> None:
        # A placeholder creditor is junk regardless of the casing it arrives in;
        # the placeholder set is stored lower-case, so the check must case-fold.
        self.assertTrue(is_junk_creditor_name("Unknown"))

    def test_lowercase_placeholder_is_junk(self) -> None:
        self.assertTrue(is_junk_creditor_name("unknown"))

    def test_real_creditor_is_not_junk(self) -> None:
        self.assertFalse(is_junk_creditor_name("WELLS FARGO"))


class TestDedupeTradelinesCaseFold(unittest.TestCase):
    def test_case_differing_duplicates_collapse(self) -> None:
        # Same account, same creditor spelled in different casing: one tradeline,
        # not two. The dedupe key is case-folded (as the pooling key is).
        out = dedupe_tradelines(
            [
                ParsedTradeline(creditor="Chase", account_number="123"),
                ParsedTradeline(creditor="CHASE", account_number="123"),
            ]
        )
        self.assertEqual(len(out), 1)

    def test_identical_duplicates_collapse(self) -> None:
        out = dedupe_tradelines(
            [
                ParsedTradeline(creditor="CHASE", account_number="123"),
                ParsedTradeline(creditor="CHASE", account_number="123"),
            ]
        )
        self.assertEqual(len(out), 1)

    def test_distinct_accounts_are_kept(self) -> None:
        out = dedupe_tradelines(
            [
                ParsedTradeline(creditor="CHASE", account_number="123"),
                ParsedTradeline(creditor="CHASE", account_number="456"),
            ]
        )
        self.assertEqual(len(out), 2)


class TestAddressSuffixAnchor(unittest.TestCase):
    def test_name_prefixed_by_suffix_is_not_address(self) -> None:
        # A borrower name that merely begins with a street-suffix token is not
        # itself an address / contact line.
        self.assertFalse(is_address_or_contact_line("Steven"))

    def test_bare_suffix_token_is_address(self) -> None:
        self.assertTrue(is_address_or_contact_line("St"))

    def test_city_state_line_is_address(self) -> None:
        self.assertTrue(is_address_or_contact_line("Memphis, TN"))


class TestBureauTagAbbreviations(unittest.TestCase):
    def test_efx_tag_maps_to_equifax(self) -> None:
        # EFX is a recognised Equifax abbreviation (it is in the tag table), so
        # an EFX column tag must resolve to equifax like the EQX form does.
        self.assertEqual(bureau_tags_from_text("EFX-B1"), {"equifax"})

    def test_eqx_tag_maps_to_equifax(self) -> None:
        self.assertEqual(bureau_tags_from_text("EQX-B1"), {"equifax"})

    def test_full_bureau_name_maps(self) -> None:
        self.assertEqual(bureau_tags_from_text("Equifax report"), {"equifax"})


class TestNumericLineRejection(unittest.TestCase):
    def test_creditor_starting_with_digit_is_plausible(self) -> None:
        # The all-numeric guard rejects lines that are entirely digits/currency;
        # a real creditor whose name merely starts with a digit must survive.
        self.assertTrue(is_plausible_creditor_line("1ST NATIONAL BANK"))

    def test_pure_numeric_line_is_rejected(self) -> None:
        self.assertFalse(is_plausible_creditor_line("123.45"))

    def test_alpha_creditor_is_plausible(self) -> None:
        self.assertTrue(is_plausible_creditor_line("CHASE"))


if __name__ == "__main__":
    unittest.main()
