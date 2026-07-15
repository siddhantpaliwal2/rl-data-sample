"""Boundary / edge-case correctness for bank-transaction enrichment.

These assert correct labels on exact-width, sentinel-amount, account-type and
fixed-layout edge inputs that the broader enrichment flow never exercises: a
cheque remark that is a bare instrument number of the exact digit width the rule
accepts, a rupee-one mandate-verification credit, a card reversal that is only
recognised for one account type, a payroll credit whose payee sits in the final
segment of a dash-delimited reference layout, and a structured transfer whose
payee comes from a specific capture group. Ordinary transactions feed values
comfortably away from these edges, so a boundary regression here stays invisible
to them.
"""
from __future__ import annotations

import unittest

import pandas as pd

from categorizationapp.BankScripts.IDBI import categorize_IDBI_transactions
from categorizationapp.BankScripts.Indusind import categorize_Indusind_transactions


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


def _idbi(rows, account_type="SAVING"):
    return categorize_IDBI_transactions(pd.DataFrame(rows).copy(), account_type)


def _indus(rows, account_type="SAVING"):
    return categorize_Indusind_transactions(pd.DataFrame(rows).copy(), account_type)


# --- fail_to_pass: one per planted defect (mutually disjoint) -------------

class TestChequePaidRemarkWidth(unittest.TestCase):
    def test_six_digit_remark_debit_is_cheque_paid(self):
        out = _indus([_row(description="RANDOMXYZNARR", type="DEBIT",
                           remark="123456")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CHEQUE_PAID")


class TestMandateVerification(unittest.TestCase):
    def test_rupee_one_mandate_is_account_verification(self):
        out = _indus([_row(description="MANDATE REGN", type="CREDIT",
                           amount=1.0)])
        self.assertEqual(out["transactionCategory"].iloc[0],
                         "ACCOUNT_VERIFICATION")


class TestPosReversalSavings(unittest.TestCase):
    def test_pos_credit_savings_is_card_payment_reversal(self):
        out = _indus([_row(description="POS TXN AT SOMESHOP", type="CREDIT",
                           amount=100.0)], account_type="SAVING")
        self.assertEqual(out["transactionCategory"].iloc[0],
                         "CARD_PAYMENT_REVERSAL")


class TestAchNachPayeeSegment(unittest.TestCase):
    def test_ach_bd_nach_payee_is_final_segment(self):
        out = _idbi([_row(description="ACH-BD-NACH-EMPLOYER NAME",
                          type="CREDIT")])
        self.assertEqual(out["partyName"].iloc[0], "Employer Name")


class TestLongReferencePayee(unittest.TestCase):
    def test_long_reference_payee_group(self):
        out = _idbi([_row(description="ABCDE1234567890 JOHN DOE", type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "John Doe")


# --- pass_to_pass: pin adjacent correct behavior (green at both states) ----

class TestChequePaidRemarkPins(unittest.TestCase):
    def test_five_digit_remark_still_cheque_paid(self):
        out = _indus([_row(description="RANDOMXYZNARR", type="DEBIT",
                           remark="12345")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CHEQUE_PAID")

    def test_seven_digit_remark_not_cheque_paid(self):
        out = _indus([_row(description="RANDOMXYZNARR", type="DEBIT",
                           remark="1234567")])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")


class TestMandatePins(unittest.TestCase):
    def test_ordinary_mandate_not_verification(self):
        out = _indus([_row(description="MANDATE REGN", type="CREDIT",
                           amount=5000.0)])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")

    def test_rupee_one_without_mandate_not_verification(self):
        out = _indus([_row(description="RANDOMXYZNARR", type="CREDIT",
                           amount=1.0)])
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")


class TestPosReversalPins(unittest.TestCase):
    def test_pos_credit_below_ten_savings_is_refund(self):
        out = _indus([_row(description="POS TXN AT SOMESHOP", type="CREDIT",
                           amount=5.0)], account_type="SAVING")
        self.assertEqual(out["transactionCategory"].iloc[0], "REFUND")

    def test_pos_credit_current_account_not_reversal(self):
        out = _indus([_row(description="POS TXN AT SOMESHOP", type="CREDIT",
                           amount=100.0)], account_type="CURRENT")
        self.assertEqual(out["transactionCategory"].iloc[0], "TRANSFER")


class TestAchNachPins(unittest.TestCase):
    def test_ach_bd_sibling_payee_segment(self):
        out = _idbi([_row(description="ACH-BD-EMPLOYER NAME", type="CREDIT")])
        self.assertEqual(out["partyName"].iloc[0], "Employer Name")

    def test_ach_bd_nach_category_still_auto_credit(self):
        out = _idbi([_row(description="ACH-BD-NACH-EMPLOYER NAME",
                          type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "AUTO_CREDIT")


class TestLongReferencePins(unittest.TestCase):
    def test_short_reference_guard_payee_empty(self):
        out = _idbi([_row(description="ABCDE123456789 JANE", type="DEBIT")])
        self.assertEqual(out["partyName"].iloc[0], "")

    def test_idbi_atm_withdrawal_category(self):
        out = _idbi([_row(description="nfs/ATM WDL", type="DEBIT",
                          amount=250.0)])
        self.assertEqual(out["transactionCategory"].iloc[0], "ATM_WITHDRAWAL")


class TestGeneralCategoryPins(unittest.TestCase):
    def test_idbi_upi_category(self):
        out = _idbi([_row(description="UPI-123 JOHN", type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "UPI")

    def test_idbi_neft_category(self):
        out = _idbi([_row(description="NEFT SOMEONE", type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "NEFT")

    def test_indus_imps_category(self):
        out = _indus([_row(description="IMPS-P2A JOHN", type="CREDIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "IMPS")

    def test_indus_card_payment_category(self):
        out = _indus([_row(description="VISA POS TXN AT IN SOMESHOP",
                           type="DEBIT")])
        self.assertEqual(out["transactionCategory"].iloc[0], "CARD_PAYMENT")


if __name__ == "__main__":
    unittest.main()
