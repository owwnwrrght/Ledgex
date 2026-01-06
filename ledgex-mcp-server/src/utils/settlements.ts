/**
 * Ledgex MCP Server - Settlement Calculation Utilities
 *
 * Handles balance calculation and debt simplification using
 * a greedy algorithm for minimal transactions.
 */

import {
  PersonBalance,
  DebtRelationship,
  GroupSummary,
  Expense,
  Person,
  Group,
} from '../models/types.js';
import { personStore, expenseStore, groupStore } from '../store/store.js';

// ============================================================================
// Balance Calculation
// ============================================================================

/**
 * Calculate the net balance for each person in a group.
 * Positive balance = person is owed money
 * Negative balance = person owes money
 */
export function calculateBalances(groupId: string): PersonBalance[] {
  const group = groupStore.get(groupId);
  if (!group) return [];

  const expenses = expenseStore.getByGroup(groupId);
  const balanceMap = new Map<string, { paid: number; owed: number }>();

  // Initialize balances for all members
  for (const member of group.members) {
    balanceMap.set(member.personId, { paid: 0, owed: 0 });
  }

  // Process each expense
  for (const expense of expenses) {
    // Track what the payer paid
    const payerBalance = balanceMap.get(expense.paidBy);
    if (payerBalance) {
      payerBalance.paid += expense.totalAmount;
    }

    // Track what each person owes
    for (const split of expense.splits) {
      const personBalance = balanceMap.get(split.personId);
      if (personBalance) {
        personBalance.owed += split.amount;
      }
    }
  }

  // Convert to PersonBalance array
  const balances: PersonBalance[] = [];
  for (const [personId, balance] of balanceMap.entries()) {
    const person = personStore.get(personId);
    balances.push({
      personId,
      personName: person?.name || 'Unknown',
      totalPaid: balance.paid,
      totalOwed: balance.owed,
      netBalance: balance.paid - balance.owed,
    });
  }

  return balances.sort((a, b) => b.netBalance - a.netBalance);
}

// ============================================================================
// Debt Simplification
// ============================================================================

/**
 * Simplify debts to minimize the number of transactions.
 * Uses a greedy algorithm: match the largest creditor with the largest debtor.
 *
 * Example: If A owes B $10 and B owes A $6, simplify to A owes B $4.
 */
export function simplifyDebts(groupId: string): DebtRelationship[] {
  const balances = calculateBalances(groupId);
  const group = groupStore.get(groupId);
  if (!group) return [];

  // Separate creditors (positive balance) and debtors (negative balance)
  const creditors: { id: string; name: string; amount: number }[] = [];
  const debtors: { id: string; name: string; amount: number }[] = [];

  for (const balance of balances) {
    if (balance.netBalance > 0) {
      creditors.push({
        id: balance.personId,
        name: balance.personName,
        amount: balance.netBalance,
      });
    } else if (balance.netBalance < 0) {
      debtors.push({
        id: balance.personId,
        name: balance.personName,
        amount: Math.abs(balance.netBalance),
      });
    }
  }

  // Sort by amount descending
  creditors.sort((a, b) => b.amount - a.amount);
  debtors.sort((a, b) => b.amount - a.amount);

  const debts: DebtRelationship[] = [];

  // Greedy matching
  let i = 0; // creditor index
  let j = 0; // debtor index

  while (i < creditors.length && j < debtors.length) {
    const creditor = creditors[i];
    const debtor = debtors[j];

    const amount = Math.min(creditor.amount, debtor.amount);

    if (amount > 0) {
      debts.push({
        from: debtor.id,
        fromName: debtor.name,
        to: creditor.id,
        toName: creditor.name,
        amount,
        currency: group.defaultCurrency,
      });
    }

    creditor.amount -= amount;
    debtor.amount -= amount;

    if (creditor.amount === 0) i++;
    if (debtor.amount === 0) j++;
  }

  return debts;
}

// ============================================================================
// Group Summary
// ============================================================================

/**
 * Generate a complete summary of a group's financial state.
 */
export function getGroupSummary(groupId: string): GroupSummary | null {
  const group = groupStore.get(groupId);
  if (!group) return null;

  const expenses = expenseStore.getByGroup(groupId);
  const balances = calculateBalances(groupId);
  const simplifiedDebts = simplifyDebts(groupId);

  const totalExpenses = expenses.reduce((sum, e) => sum + e.totalAmount, 0);

  return {
    groupId,
    groupName: group.name,
    totalExpenses,
    expenseCount: expenses.length,
    memberCount: group.members.length,
    balances,
    simplifiedDebts,
    currency: group.defaultCurrency,
  };
}

// ============================================================================
// Balance Between Two People
// ============================================================================

/**
 * Get the net balance between two specific people across all groups.
 */
export function getBalanceBetween(
  personAId: string,
  personBId: string
): { amount: number; currency: string; aOwesB: boolean } | null {
  // Find groups where both people are members
  const groupsA = groupStore.getGroupsForPerson(personAId);
  const sharedGroups = groupsA.filter(g =>
    g.members.some(m => m.personId === personBId)
  );

  if (sharedGroups.length === 0) return null;

  let netBalance = 0; // Positive = A owes B, Negative = B owes A
  let currency = 'USD';

  for (const group of sharedGroups) {
    const expenses = expenseStore.getByGroup(group.id);
    currency = group.defaultCurrency;

    for (const expense of expenses) {
      // If A paid, check what B owes
      if (expense.paidBy === personAId) {
        const bSplit = expense.splits.find(s => s.personId === personBId);
        if (bSplit) {
          netBalance -= bSplit.amount; // B owes A
        }
      }

      // If B paid, check what A owes
      if (expense.paidBy === personBId) {
        const aSplit = expense.splits.find(s => s.personId === personAId);
        if (aSplit) {
          netBalance += aSplit.amount; // A owes B
        }
      }
    }
  }

  return {
    amount: Math.abs(netBalance),
    currency,
    aOwesB: netBalance > 0,
  };
}

// ============================================================================
// Formatting Helpers
// ============================================================================

/**
 * Format an amount in minor units to a readable string.
 */
export function formatMoney(amount: number, currency: string): string {
  const currencies: Record<string, { symbol: string; decimals: number }> = {
    USD: { symbol: '$', decimals: 2 },
    EUR: { symbol: '€', decimals: 2 },
    GBP: { symbol: '£', decimals: 2 },
    JPY: { symbol: '¥', decimals: 0 },
    CAD: { symbol: 'C$', decimals: 2 },
    AUD: { symbol: 'A$', decimals: 2 },
  };

  const config = currencies[currency] || { symbol: currency + ' ', decimals: 2 };
  const divisor = Math.pow(10, config.decimals);
  const value = amount / divisor;

  return `${config.symbol}${value.toFixed(config.decimals)}`;
}

/**
 * Parse a money string to minor units.
 */
export function parseMoney(value: string | number, currency: string = 'USD'): number {
  const currencies: Record<string, number> = {
    USD: 2, EUR: 2, GBP: 2, JPY: 0, CAD: 2, AUD: 2,
  };

  const decimals = currencies[currency] ?? 2;
  const multiplier = Math.pow(10, decimals);

  if (typeof value === 'number') {
    return Math.round(value * multiplier);
  }

  // Remove currency symbols and parse
  const cleaned = value.replace(/[$€£¥,\s]/g, '');
  const parsed = parseFloat(cleaned);

  if (isNaN(parsed)) return 0;
  return Math.round(parsed * multiplier);
}
