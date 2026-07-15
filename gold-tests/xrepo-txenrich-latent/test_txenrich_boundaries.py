"""Boundary / edge-case correctness for bank-transaction enrichment.

These assert correct labels on exact-length, adjacency, account-type and
fixed-layout edge inputs that the broader enrichment flow never exercises: a
cheque-deposit remark whose length sits exactly on the value its digit layout
implies, a six-digit salary credit in a savings account, an offsetting credit
that lands directly after its matching debit, a direction-prefixed transfer
whose payee name follows the direction keyword, and a structured bill payee
that sits in the final segment of its layout. Ordinary transactions feed values
comfortably away from these edges, so a boundary regression here stays invisible
to them.
"""
from __future__ import annotations

import unittest

import pandas as pd

from categorizationapp.BankScripts.HDFC import categorize_HDFC_transactions
from categorizationapp.BankScripts.ICICI import categorize_ICICI_transactions


def _row(**over):
    row = {
        "description": "NEUTRALNARR",
        "type": "CREDIT",
        "amount": 5000.0,
        "balanceAfterTransaction": 10000.0,
        "remark": "",
    }
    row.update(over)
    return row


def _hdfc(rows, account_type="SAVING"):
    return categorize_HDFC_transactions(pd.DataFrame(rows).copy(), account_type)


def _icici(rows, account_type="SAVING"):
    return categorize_ICICI_transactions(pd.DataFrame(rows).copy(), account_type)


# --- fail_to_pass: one per planted defect (mutually disjoint) -------------

class TestChequeDepositRemarkLength(unittest.TestCase):
    def test_sixteen_char_zero_prefixed_remark_is_cheque_deposit(self):
        out = _hdfc([_row(description="RANDOMTXNNARR", type="CREDIT",
                          remark="0000000000012345")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CHEQUE_DEPOSIT")


class TestSixDigitSavingsSalary(unittest.TestCase):
    def test_six_digit_credit_in_savings_is_salary(self):
        out = _hdfc([_row(description="123456", amount=45000.0, type="CREDIT")],
                    account_type="SAVING")
        self.assertEqual(out["transactionSubcategory"].iloc[0], "SALARY")


class TestAdjacentReversal(unittest.TestCase):
    def test_credit_mirroring_prior_debit_is_reversal(self):
        out = _hdfc([
            _row(description="NEFT PAYMENT ABC", amount=777.0, type="DEBIT"),
            _row(description="NEFT PAYMENT ABC", amount=777.0, type="CREDIT"),
        ])
        self.assertEqual(out["transactionCategory"].iloc[1], "REVERSAL")


class TestTrfPayeeDirectionPrefix(unittest.TestCase):
    def test_transfer_payee_follows_direction_keyword(self):
        out = _icici([_row(description="TRFR TO: JOHN DOE", type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "John Doe")


class TestBilInftPayeeSegment(unittest.TestCase):
    def test_payee_is_final_segment(self):
        out = _icici([_row(description="BIL/INFT/000123/JOHN DOE", type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "John Doe")


# --- pass_to_pass: pin adjacent correct behavior (green at both states) ----

class TestChequeDepositRemarkPins(unittest.TestCase):
    def test_fifteen_char_remark_is_not_cheque_deposit(self):
        out = _hdfc([_row(description="RANDOMTXNNARR", type="CREDIT",
                          remark="000000000001234")])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")

    def test_sixteen_char_non_zero_remark_is_not_cheque_deposit(self):
        out = _hdfc([_row(description="RANDOMTXNNARR", type="CREDIT",
                          remark="1234567890123456")])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")


class TestSalaryPins(unittest.TestCase):
    def test_six_digit_credit_in_current_is_not_salary(self):
        out = _hdfc([_row(description="123456", amount=45000.0, type="CREDIT")],
                    account_type="CURRENT")
        self.assertNotEqual(out["transactionSubcategory"].iloc[0], "SALARY")

    def test_a2aint_credit_still_salary(self):
        out = _hdfc([_row(description="A2AINT01-EMPLOYER", type="CREDIT")])
        self.assertEqual(out["transactionSubcategory"].iloc[0], "SALARY")


class TestReversalPins(unittest.TestCase):
    def test_lone_credit_without_prior_debit_is_not_reversal(self):
        out = _hdfc([_row(description="NEFT PAYMENT ABC", amount=777.0, type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")

    def test_mismatched_amount_is_not_reversal(self):
        out = _hdfc([
            _row(description="NEFT PAYMENT ABC", amount=500.0, type="DEBIT"),
            _row(description="NEFT PAYMENT ABC", amount=777.0, type="CREDIT"),
        ])
        self.assertEqual(out["transactionCategory"].iloc[1], "TRANSFER")


class TestTrfPayeePins(unittest.TestCase):
    def test_trfr_transaction_category_still_transfer(self):
        out = _icici([_row(description="TRFR TO: JOHN DOE", type="DEBIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")

    def test_adjacent_slash_transfer_payee_extraction_intact(self):
        out = _icici([_row(description="TRF/RAVI KUMAR", type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "Ravi Kumar")


class TestPayeePins(unittest.TestCase):
    def test_upi_payee_extraction_unaffected(self):
        # UPI payees come off a different slice (untouched by the fix): the name
        # is the final segment of a four-part UPI description.
        out = _icici([_row(description="UPI/000111/SOMEREF/JANE SMITH", type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "Jane Smith")

    def test_bil_inft_with_extra_segment_uses_other_branch(self):
        out = _icici([_row(description="BIL/INFT/000123/JOHN DOE/EXTRA", type="DEBIT")])
        self.assertNotEqual(out["partyName"].iloc[0], "000123")


class TestGeneralCategoryPins(unittest.TestCase):
    def test_icici_cash_withdrawal_category(self):
        out = _icici([_row(description="CASH WDL ATM", type="DEBIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "ATM_WITHDRAWAL")

    def test_hdfc_pos_card_payment_category(self):
        out = _hdfc([_row(description="POS 1234XX5678 SOMESHOP", type="DEBIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CARD_PAYMENT")


if __name__ == "__main__":
    unittest.main()
