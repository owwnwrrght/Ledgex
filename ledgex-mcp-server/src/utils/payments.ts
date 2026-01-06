/**
 * Ledgex MCP Server - Payment Link Utilities
 *
 * Generates deep links for various payment providers.
 */

import { formatMoney } from './settlements.js';

// ============================================================================
// Venmo
// ============================================================================

export interface VenmoPaymentParams {
  recipientUsername: string;
  amount: number;       // In minor units (cents)
  currency: string;
  note: string;
}

/**
 * Generate a Venmo payment deep link.
 * Format: venmo://paycharge?txn=pay&recipients=USERNAME&amount=AMOUNT&note=NOTE
 */
export function generateVenmoLink(params: VenmoPaymentParams): string {
  const { recipientUsername, amount, currency, note } = params;

  // Convert from minor units to decimal
  const decimals = currency === 'JPY' ? 0 : 2;
  const amountDecimal = amount / Math.pow(10, decimals);

  const encodedNote = encodeURIComponent(note);
  const encodedRecipient = encodeURIComponent(recipientUsername);

  return `venmo://paycharge?txn=pay&recipients=${encodedRecipient}&amount=${amountDecimal.toFixed(2)}&note=${encodedNote}`;
}

/**
 * Generate a Venmo web link (fallback for non-mobile).
 */
export function generateVenmoWebLink(params: VenmoPaymentParams): string {
  const { recipientUsername, amount, currency, note } = params;

  const decimals = currency === 'JPY' ? 0 : 2;
  const amountDecimal = amount / Math.pow(10, decimals);

  const encodedNote = encodeURIComponent(note);

  return `https://venmo.com/${recipientUsername}?txn=pay&amount=${amountDecimal.toFixed(2)}&note=${encodedNote}`;
}

// ============================================================================
// PayPal
// ============================================================================

export interface PayPalPaymentParams {
  recipientEmail: string;
  amount: number;       // In minor units
  currency: string;
  description: string;
}

/**
 * Generate a PayPal.me link.
 * Note: PayPal.me requires the recipient to have set up a PayPal.me username.
 */
export function generatePayPalLink(params: PayPalPaymentParams): string {
  const { recipientEmail, amount, currency } = params;

  const decimals = currency === 'JPY' ? 0 : 2;
  const amountDecimal = amount / Math.pow(10, decimals);

  // PayPal.me format: paypal.me/username/amount
  // Since we have email, we'll use the send money URL
  return `https://www.paypal.com/paypalme/${encodeURIComponent(recipientEmail)}/${amountDecimal.toFixed(2)}${currency}`;
}

// ============================================================================
// Payment Reminder Messages
// ============================================================================

export interface ReminderParams {
  fromName: string;
  toName: string;
  amount: number;
  currency: string;
  groupName?: string;
  daysOutstanding?: number;
}

/**
 * Generate a friendly payment reminder message.
 */
export function generateReminderMessage(params: ReminderParams): string {
  const { fromName, toName, amount, currency, groupName, daysOutstanding } = params;

  const formattedAmount = formatMoney(amount, currency);
  const groupContext = groupName ? ` for ${groupName}` : '';

  const messages = [
    `Hey ${fromName}! Just a friendly reminder that you owe ${toName} ${formattedAmount}${groupContext}. No rush, but wanted to keep our ledger clean!`,
    `Quick reminder: ${formattedAmount} is still pending${groupContext}. ${toName} would appreciate settling up when you get a chance!`,
    `Heads up ${fromName} - ${formattedAmount} owed to ${toName}${groupContext}. Let's square up soon!`,
  ];

  // Add urgency based on days outstanding
  if (daysOutstanding && daysOutstanding > 30) {
    return `Hey ${fromName}, this is a reminder about ${formattedAmount} owed to ${toName}${groupContext}. It's been ${daysOutstanding} days - would be great to settle this soon!`;
  }

  return messages[Math.floor(Math.random() * messages.length)];
}

/**
 * Generate a settlement confirmation message.
 */
export function generateSettlementConfirmation(
  fromName: string,
  toName: string,
  amount: number,
  currency: string,
  method: string
): string {
  const formattedAmount = formatMoney(amount, currency);
  return `${fromName} paid ${toName} ${formattedAmount} via ${method}. All settled up!`;
}
