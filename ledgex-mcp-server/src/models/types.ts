/**
 * Ledgex MCP Server - Data Models
 *
 * These models represent the core domain objects for expense splitting.
 * Designed to be compatible with the Ledgex iOS app while optimized for
 * AI agent interactions.
 */

// ============================================================================
// Core Identifiers
// ============================================================================

export type PersonId = string;
export type GroupId = string;
export type ExpenseId = string;
export type SettlementId = string;
export type ReceiptId = string;

// ============================================================================
// Currency & Money
// ============================================================================

export interface Currency {
  code: string;      // ISO 4217 code (USD, EUR, GBP, etc.)
  symbol: string;    // Display symbol ($, €, £, etc.)
  decimals: number;  // Decimal places (2 for most, 0 for JPY, KRW)
}

export const SUPPORTED_CURRENCIES: Record<string, Currency> = {
  USD: { code: 'USD', symbol: '$', decimals: 2 },
  EUR: { code: 'EUR', symbol: '€', decimals: 2 },
  GBP: { code: 'GBP', symbol: '£', decimals: 2 },
  CAD: { code: 'CAD', symbol: 'C$', decimals: 2 },
  AUD: { code: 'AUD', symbol: 'A$', decimals: 2 },
  JPY: { code: 'JPY', symbol: '¥', decimals: 0 },
  CNY: { code: 'CNY', symbol: '¥', decimals: 2 },
  MXN: { code: 'MXN', symbol: '$', decimals: 2 },
  INR: { code: 'INR', symbol: '₹', decimals: 2 },
  CHF: { code: 'CHF', symbol: 'Fr', decimals: 2 },
};

export interface Money {
  amount: number;        // Amount in minor units (cents for USD)
  currency: string;      // Currency code
}

// ============================================================================
// People & Groups
// ============================================================================

export interface Person {
  id: PersonId;
  name: string;
  email?: string;
  phone?: string;
  venmoUsername?: string;
  paypalEmail?: string;
  createdAt: Date;
}

export interface GroupMember {
  personId: PersonId;
  nickname?: string;     // Optional nickname within this group
  joinedAt: Date;
}

export interface Group {
  id: GroupId;
  name: string;
  description?: string;
  members: GroupMember[];
  defaultCurrency: string;
  createdAt: Date;
  updatedAt: Date;

  // Trip/Event mode
  isTrip: boolean;
  tripStartDate?: Date;
  tripEndDate?: Date;
  tripLocation?: string;
}

// ============================================================================
// Expenses & Splits
// ============================================================================

export type ExpenseCategory =
  | 'food'
  | 'drinks'
  | 'transportation'
  | 'accommodation'
  | 'entertainment'
  | 'shopping'
  | 'groceries'
  | 'utilities'
  | 'services'
  | 'other';

export type SplitType =
  | 'equal'           // Split equally among all participants
  | 'exact'           // Exact amounts per person
  | 'percentage'      // Percentage-based split
  | 'shares'          // Share-based (e.g., 2 shares vs 1 share)
  | 'itemized';       // By specific items (from receipt)

export interface ExpenseSplit {
  personId: PersonId;
  amount: number;        // Amount owed (in minor units)
  percentage?: number;   // If percentage split
  shares?: number;       // If share-based split
  items?: string[];      // If itemized, which items
}

export interface Expense {
  id: ExpenseId;
  groupId: GroupId;
  description: string;
  totalAmount: number;   // Total in minor units
  currency: string;
  category: ExpenseCategory;

  // Who paid
  paidBy: PersonId;
  paidByMultiple?: { personId: PersonId; amount: number }[];  // If multiple payers

  // How to split
  splitType: SplitType;
  splits: ExpenseSplit[];

  // Tax and tip handling
  subtotal?: number;     // Pre-tax/tip amount
  tax?: number;
  tip?: number;

  // Metadata
  date: Date;
  receiptId?: ReceiptId;
  notes?: string;
  createdAt: Date;
  updatedAt: Date;
}

// ============================================================================
// Receipt Parsing
// ============================================================================

export interface ReceiptLineItem {
  description: string;
  quantity: number;
  unitPrice: number;     // In minor units
  totalPrice: number;    // In minor units
  category?: ExpenseCategory;
}

export interface ParsedReceipt {
  id: ReceiptId;
  merchantName?: string;
  merchantAddress?: string;
  date?: Date;

  lineItems: ReceiptLineItem[];
  subtotal: number;
  tax?: number;
  tip?: number;
  total: number;

  currency: string;
  rawText?: string;      // Original OCR text
  confidence: number;    // 0-1 confidence score

  createdAt: Date;
}

export interface ItemAssignment {
  itemIndex: number;     // Index in lineItems array
  assignedTo: PersonId[];
  splitType: 'equal' | 'custom';
  customSplits?: { personId: PersonId; amount: number }[];
}

// ============================================================================
// Settlements & Payments
// ============================================================================

export type PaymentStatus =
  | 'pending'
  | 'requested'
  | 'completed'
  | 'cancelled';

export type PaymentMethod =
  | 'venmo'
  | 'paypal'
  | 'cash'
  | 'bank_transfer'
  | 'other';

export interface Settlement {
  id: SettlementId;
  groupId: GroupId;
  from: PersonId;        // Who owes
  to: PersonId;          // Who is owed
  amount: number;        // In minor units
  currency: string;

  status: PaymentStatus;
  paymentMethod?: PaymentMethod;
  paymentLink?: string;  // Generated Venmo/PayPal link

  // For tracking
  requestedAt?: Date;
  completedAt?: Date;
  notes?: string;

  createdAt: Date;
  updatedAt: Date;
}

// ============================================================================
// Balances (Computed)
// ============================================================================

export interface PersonBalance {
  personId: PersonId;
  personName: string;
  totalPaid: number;      // Total amount paid for group
  totalOwed: number;      // Total amount owed to group
  netBalance: number;     // Positive = owed money, negative = owes money
}

export interface DebtRelationship {
  from: PersonId;
  fromName: string;
  to: PersonId;
  toName: string;
  amount: number;
  currency: string;
}

export interface GroupSummary {
  groupId: GroupId;
  groupName: string;
  totalExpenses: number;
  expenseCount: number;
  memberCount: number;
  balances: PersonBalance[];
  simplifiedDebts: DebtRelationship[];
  currency: string;
}

// ============================================================================
// Quick Expense (No Receipt)
// ============================================================================

export interface QuickExpense {
  description: string;
  amount: number;
  currency: string;
  paidBy: PersonId;
  splitWith: PersonId[];
  splitType: SplitType;
  category?: ExpenseCategory;
  date?: Date;
  notes?: string;
}

// ============================================================================
// Spending Analytics
// ============================================================================

export interface SpendingByCategory {
  category: ExpenseCategory;
  total: number;
  count: number;
  percentage: number;
}

export interface SpendingPattern {
  groupId: GroupId;
  period: 'week' | 'month' | 'trip' | 'all';
  totalSpent: number;
  byCategory: SpendingByCategory[];
  topSpender: { personId: PersonId; amount: number };
  averageExpense: number;
  largestExpense: { expenseId: ExpenseId; amount: number; description: string };
}
