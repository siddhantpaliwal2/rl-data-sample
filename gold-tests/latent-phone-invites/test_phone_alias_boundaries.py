"""Boundary / edge-case correctness for phone normalization and loan-type resolution.

These assert the correct outputs on unusual-but-legitimate inputs the broader CRM
suite never exercises: a number that no candidate region recognizes as valid (so the
earliest region tried must win), a number carrying the ``00`` international access
prefix, a number whose correct country depends on the configured default region, a
legacy loan-type id no longer in the catalog, and a canonical loan-type id typed in
mixed case. The service-level and CSV-import tests only ever feed values comfortably
away from these edges, so a regression here stays invisible to them.

The phone functions are pure given the ``phonenumbers`` library and the loan-type
resolvers are pure table lookups, so every case below is a direct call with no mocks.
"""

from __future__ import annotations

import unittest

from agent.integrations.cartesia.phone import (
    normalize_phone_to_e164,
    try_normalize_phone_to_e164,
)
from agent.services.smbcontacts.loan_types import (
    loan_type_label,
    resolve_loan_type,
)


class TestUnrecognizedNumberPrefersDefaultRegion(unittest.TestCase):
    def test_number_valid_in_no_region_keeps_default_interpretation(self) -> None:
        # These digits are a *possible* but not *valid* subscriber number in every
        # candidate region. With no valid match anywhere, the earliest region tried
        # (the configured default) must decide the country code, not whichever
        # region happens to sit last in the shared fallback list.
        self.assertEqual(
            try_normalize_phone_to_e164("1201234567", default_region="US"),
            "+11201234567",
        )


class TestZeroZeroInternationalPrefix(unittest.TestCase):
    def test_double_zero_access_prefix_is_treated_as_plus(self) -> None:
        # A number dialed with the 00 international access code must normalize
        # exactly as its + form would: 0044 <national> -> +44 <national>.
        self.assertEqual(
            normalize_phone_to_e164("00442079460958"),
            "+442079460958",
        )


class TestDefaultRegionPreference(unittest.TestCase):
    def test_default_region_wins_over_earlier_fallback_region(self) -> None:
        # The same digits form a valid subscriber number in several regions; the
        # explicitly configured default region must be preferred over whatever
        # region comes first in the shared fallback list.
        self.assertEqual(
            try_normalize_phone_to_e164("2079460958", default_region="GB"),
            "+442079460958",
        )


class TestLegacyLoanTypeLabel(unittest.TestCase):
    def test_unknown_id_is_humanized_word_by_word(self) -> None:
        # An id no longer in the catalog is humanized for display: underscores
        # become spaces and every word is capitalized (not run together).
        self.assertEqual(loan_type_label("hard_money"), "Hard Money")


class TestMixedCaseCanonicalLoanId(unittest.TestCase):
    def test_mixed_case_id_resolves_to_stored_lowercase_id(self) -> None:
        # A canonical id typed in mixed case must resolve to the stored lowercase
        # id, not echo the raw casing straight back to the caller.
        self.assertEqual(resolve_loan_type("Working_Capital"), "working_capital")


if __name__ == "__main__":
    unittest.main()
