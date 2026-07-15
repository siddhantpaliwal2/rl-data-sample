"""Boundary / edge-case correctness for bank-transaction enrichment.

These assert correct labels and payee names on narrow edge inputs that the
broader enrichment flow never exercises: a cheque payment whose statement note
is a bare instrument number of the exact digit width the rule accepts, an
electronic credit whose sender name sits in a single capture group of its
reference, a cleared cheque whose payee is the final segment of a dash-delimited
layout, a nominal account-confirmation credit of exactly one rupee, and a
person-to-person credit whose payee is a specific slash-delimited segment.
Ordinary transactions feed values comfortably away from these edges, so a
regression here stays invisible to them.
"""
from __future__ import annotations

import unittest

import pandas as pd

from categorizationapp.BankScripts.PNB import categorize_PNB_transactions
from categorizationapp.BankScripts.Canara import categorize_Canara_transactions


def _row(**over):
    row = {
        "description": "ZQXNEUTRALROW",
        "type": "CREDIT",
        "amount": 5000.0,
        "balanceAfterTransaction": 10000.0,
        "remark": "",
    }
    row.update(over)
    return row


def _pnb(rows, account_type="SAVING"):
    return categorize_PNB_transactions(pd.DataFrame(rows).copy(), account_type)


def _can(rows, account_type="SAVING"):
    return categorize_Canara_transactions(pd.DataFrame(rows).copy(), account_type)


# --- fail_to_pass: one per planted defect (mutually disjoint) -------------

class TestChequePaidRemarkWidth(unittest.TestCase):
    def test_six_digit_remark_debit_is_cheque_paid(self):
        out = _pnb([_row(description="ZQXNEUTRALROW", type="DEBIT",
                         remark="123456")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CHEQUE_PAID")


class TestNeftPayeeExtraction(unittest.TestCase):
    def test_neft_credit_payee_name(self):
        out = _pnb([_row(description="NEFT JOHN DOE", type="CREDIT")])
        self.assertEqual(out["partyName"].iloc[0], "John Doe")


class TestChequePaidPayeeSegment(unittest.TestCase):
    def test_chq_paid_payee_is_final_segment(self):
        out = _can([_row(description="CHQ PAID-MICR CLG-JOHN DOE",
                         type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "John Doe")


class TestAccountVerificationSentinel(unittest.TestCase):
    def test_rupee_one_validation_is_verification(self):
        out = _can([_row(description="ACCOUNT VALIDATION", type="CREDIT",
                         amount=1.0)])
        self.assertEqual(out["transactionCategory"].iloc[0],
                         "ACCOUNT_VERIFICATION")


class TestUpiPayeeSegment(unittest.TestCase):
    def test_upi_credit_payee_name(self):
        out = _can([_row(description="UPI/CR/REF123456/JOHN DOE",
                         type="CREDIT")])
        self.assertEqual(out["partyName"].iloc[0], "John Doe")


# --- pass_to_pass: pin adjacent correct behavior (green at both states) ----

class TestChequePaidRemarkPins(unittest.TestCase):
    def test_five_digit_remark_still_cheque_paid(self):
        out = _pnb([_row(description="ZQXNEUTRALROW", type="DEBIT",
                         remark="12345")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CHEQUE_PAID")

    def test_seven_digit_remark_not_cheque_paid(self):
        out = _pnb([_row(description="ZQXNEUTRALROW", type="DEBIT",
                         remark="1234567")])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")

    def test_six_digit_credit_remark_is_cheque_deposit(self):
        out = _pnb([_row(description="ZQXNEUTRALROW", type="CREDIT",
                         remark="123456")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CHEQUE_DEPOSIT")


class TestNeftPayeePins(unittest.TestCase):
    def test_neft_credit_category_still_neft(self):
        out = _pnb([_row(description="NEFT JOHN DOE", type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "NEFT")

    def test_neft_ib_ow_payee_unaffected(self):
        out = _pnb([_row(description="NEFT-IB-OW/REF/JANE SMITH",
                         type="CREDIT")])
        self.assertEqual(out["partyName"].iloc[0], "Jane Smith")


class TestChequePaidPayeePins(unittest.TestCase):
    def test_chq_paid_category_still_cheque_paid(self):
        out = _can([_row(description="CHQ PAID-MICR CLG-JOHN DOE",
                         type="DEBIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CHEQUE_PAID")

    def test_chq_paid_home_clearing_sibling_payee(self):
        out = _can([_row(description="Chq Paid-Home Clearing-JANE SMITH",
                         type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "Jane Smith")


class TestVerificationPins(unittest.TestCase):
    def test_high_amount_validation_not_verification(self):
        out = _can([_row(description="ACCOUNT VALIDATION", type="CREDIT",
                         amount=5000.0)])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")

    def test_rupee_one_without_validation_not_verification(self):
        out = _can([_row(description="ZQXNEUTRALROW", type="CREDIT",
                         amount=1.0)])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")


class TestUpiPayeePins(unittest.TestCase):
    def test_upi_credit_category_still_upi(self):
        out = _can([_row(description="UPI/CR/REF123456/JOHN DOE",
                         type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "UPI")

    def test_upv_dr_sibling_payee_unaffected(self):
        out = _can([_row(description="UPV/DR/REF/JANE DOE", type="CREDIT")])
        self.assertEqual(out["partyName"].iloc[0], "Jane Doe")


class TestGeneralCategoryPins(unittest.TestCase):
    def test_pnb_imps_category(self):
        out = _pnb([_row(description="IMPS SOMEBODY", type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "IMPS")

    def test_pnb_rtgs_category(self):
        out = _pnb([_row(description="RTGS SOMEONE", type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "RTGS")

    def test_canara_atm_withdrawal_category(self):
        out = _can([_row(description="ATM WDR SOMEATM", type="DEBIT",
                         amount=250.0)])
        self.assertEqual(out["transactionCategory"].iloc[0], "ATM_WITHDRAWAL")


if __name__ == "__main__":
    unittest.main()
