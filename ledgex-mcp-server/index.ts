/**
 * Ledgex MCP Server
 *
 * An MCP server for AI-powered expense splitting. Enables natural language
 * interactions for receipt parsing, expense tracking, group management,
 * and settlement generation.
 *
 * Built for the Ledgex bill-splitting app.
 */

import { MCPServer } from "mcp-use/server";
import { z } from "zod";

import {
  personStore,
  groupStore,
  expenseStore,
  settlementStore,
  receiptStore,
  store,
} from "./src/store/store.js";

import {
  calculateBalances,
  simplifyDebts,
  getGroupSummary,
  getBalanceBetween,
  formatMoney,
  parseMoney,
} from "./src/utils/settlements.js";

import {
  generateVenmoLink,
  generateVenmoWebLink,
  generateReminderMessage,
  generateSettlementConfirmation,
} from "./src/utils/payments.js";

import type {
  ExpenseCategory,
  SplitType,
  ParsedReceipt,
  ReceiptLineItem,
  ExpenseSplit,
  ItemAssignment,
} from "./src/models/types.js";

// ============================================================================
// Server Configuration
// ============================================================================

const server = new MCPServer({
  name: "ledgex",
  version: "1.0.0",
  description: "AI-powered expense splitting for groups. Parse receipts, track expenses, split costs, and settle up with friends.",
  baseUrl: process.env.MCP_URL || "http://localhost:3000",
});

// ============================================================================
// PEOPLE MANAGEMENT TOOLS
// ============================================================================

server.tool(
  {
    name: "create_person",
    description: "Create a new person who can participate in expense splitting. Use this when adding a new friend, roommate, or group member for the first time.",
    schema: z.object({
      name: z.string().describe("Person's name"),
      email: z.string().email().optional().describe("Email address"),
      phone: z.string().optional().describe("Phone number"),
      venmoUsername: z.string().optional().describe("Venmo username for payments"),
      paypalEmail: z.string().email().optional().describe("PayPal email for payments"),
    }),
  },
  async ({ name, email, phone, venmoUsername, paypalEmail }) => {
    // Check if person already exists
    const existing = personStore.getByName(name);
    if (existing) {
      return {
        content: [{
          type: "text",
          text: `Person "${name}" already exists with ID: ${existing.id}. Use update_person to modify their details.`,
        }],
      };
    }

    const person = personStore.create({ name, email, phone, venmoUsername, paypalEmail });

    return {
      content: [{
        type: "text",
        text: `Created person "${person.name}" (ID: ${person.id})${venmoUsername ? ` with Venmo: @${venmoUsername}` : ""}`,
      }],
    };
  }
);

server.tool(
  {
    name: "list_people",
    description: "List all people in the system. Useful for seeing who's available for expense splitting.",
    schema: z.object({}),
  },
  async () => {
    const people = personStore.list();

    if (people.length === 0) {
      return {
        content: [{
          type: "text",
          text: "No people found. Use create_person to add someone.",
        }],
      };
    }

    const list = people.map(p => {
      const details = [p.name];
      if (p.venmoUsername) details.push(`Venmo: @${p.venmoUsername}`);
      if (p.email) details.push(`Email: ${p.email}`);
      return `- ${details.join(" | ")} (ID: ${p.id})`;
    }).join("\n");

    return {
      content: [{
        type: "text",
        text: `**People (${people.length}):**\n${list}`,
      }],
    };
  }
);

server.tool(
  {
    name: "update_person",
    description: "Update a person's details like Venmo username, email, or phone number.",
    schema: z.object({
      personId: z.string().optional().describe("Person's ID"),
      name: z.string().optional().describe("Person's name (used to find them if no ID provided)"),
      newName: z.string().optional().describe("New name for the person"),
      email: z.string().email().optional().describe("New email address"),
      phone: z.string().optional().describe("New phone number"),
      venmoUsername: z.string().optional().describe("New Venmo username"),
      paypalEmail: z.string().email().optional().describe("New PayPal email"),
    }),
  },
  async ({ personId, name, newName, email, phone, venmoUsername, paypalEmail }) => {
    let person = personId ? personStore.get(personId) : name ? personStore.getByName(name) : undefined;

    if (!person) {
      return {
        content: [{
          type: "text",
          text: `Person not found. Please provide a valid person ID or name.`,
        }],
      };
    }

    const updates: any = {};
    if (newName) updates.name = newName;
    if (email) updates.email = email;
    if (phone) updates.phone = phone;
    if (venmoUsername) updates.venmoUsername = venmoUsername;
    if (paypalEmail) updates.paypalEmail = paypalEmail;

    const updated = personStore.update(person.id, updates);

    return {
      content: [{
        type: "text",
        text: `Updated ${updated?.name}: ${Object.entries(updates).map(([k, v]) => `${k}=${v}`).join(", ")}`,
      }],
    };
  }
);

// ============================================================================
// GROUP MANAGEMENT TOOLS
// ============================================================================

server.tool(
  {
    name: "create_group",
    description: "Create a new expense-sharing group. Use this for roommates, trips, dinner groups, or any situation where multiple people share costs. You can specify members by name - they'll be created automatically if they don't exist.",
    schema: z.object({
      name: z.string().describe("Group name (e.g., 'Vegas Trip 2024', 'Roommates', 'Dinner Crew')"),
      description: z.string().optional().describe("Brief description of the group"),
      memberNames: z.array(z.string()).describe("Names of people to add to the group"),
      currency: z.string().default("USD").describe("Default currency (USD, EUR, GBP, etc.)"),
      isTrip: z.boolean().default(false).describe("Is this for a specific trip/event?"),
      tripLocation: z.string().optional().describe("Trip location if applicable"),
      tripStartDate: z.string().optional().describe("Trip start date (YYYY-MM-DD)"),
      tripEndDate: z.string().optional().describe("Trip end date (YYYY-MM-DD)"),
    }),
  },
  async ({ name, description, memberNames, currency, isTrip, tripLocation, tripStartDate, tripEndDate }) => {
    // Get or create all members
    const members = memberNames.map(memberName => {
      const person = personStore.getOrCreate(memberName);
      return {
        personId: person.id,
        joinedAt: new Date(),
      };
    });

    const group = groupStore.create({
      name,
      description,
      members,
      defaultCurrency: currency,
      isTrip,
      tripLocation,
      tripStartDate: tripStartDate ? new Date(tripStartDate) : undefined,
      tripEndDate: tripEndDate ? new Date(tripEndDate) : undefined,
    });

    const memberList = memberNames.join(", ");
    const tripInfo = isTrip ? ` (Trip to ${tripLocation || "TBD"})` : "";

    return {
      content: [{
        type: "text",
        text: `Created group "${group.name}"${tripInfo} with ${members.length} members: ${memberList}. Group ID: ${group.id}`,
      }],
    };
  }
);

server.tool(
  {
    name: "list_groups",
    description: "List all expense-sharing groups. Shows active trips, roommate groups, and other expense pools.",
    schema: z.object({
      activeTripsOnly: z.boolean().default(false).describe("Only show currently active trips"),
    }),
  },
  async ({ activeTripsOnly }) => {
    const groups = activeTripsOnly ? groupStore.getActiveTrips() : groupStore.list();

    if (groups.length === 0) {
      return {
        content: [{
          type: "text",
          text: activeTripsOnly
            ? "No active trips found. Use create_group with isTrip=true to start one."
            : "No groups found. Use create_group to create one.",
        }],
      };
    }

    const list = groups.map(g => {
      const memberNames = g.members.map(m => {
        const person = personStore.get(m.personId);
        return person?.name || "Unknown";
      }).join(", ");

      const expenses = expenseStore.getByGroup(g.id);
      const total = expenses.reduce((sum, e) => sum + e.totalAmount, 0);

      let info = `**${g.name}** (${g.members.length} members)`;
      if (g.isTrip && g.tripLocation) info += ` - ${g.tripLocation}`;
      info += `\n  Members: ${memberNames}`;
      info += `\n  Total expenses: ${formatMoney(total, g.defaultCurrency)} (${expenses.length} items)`;
      info += `\n  ID: ${g.id}`;

      return info;
    }).join("\n\n");

    return {
      content: [{
        type: "text",
        text: `**Groups (${groups.length}):**\n\n${list}`,
      }],
    };
  }
);

server.tool(
  {
    name: "add_group_member",
    description: "Add a new person to an existing group.",
    schema: z.object({
      groupId: z.string().optional().describe("Group ID"),
      groupName: z.string().optional().describe("Group name (alternative to ID)"),
      personName: z.string().describe("Name of person to add"),
      nickname: z.string().optional().describe("Optional nickname for this person in the group"),
    }),
  },
  async ({ groupId, groupName, personName, nickname }) => {
    const group = groupId ? groupStore.get(groupId) : groupName ? groupStore.getByName(groupName) : undefined;

    if (!group) {
      return {
        content: [{
          type: "text",
          text: "Group not found. Please provide a valid group ID or name.",
        }],
      };
    }

    const person = personStore.getOrCreate(personName);
    const updated = groupStore.addMember(group.id, person.id, nickname);

    return {
      content: [{
        type: "text",
        text: `Added ${person.name} to group "${updated?.name}".`,
      }],
    };
  }
);

// ============================================================================
// RECEIPT PARSING TOOLS
// ============================================================================

server.tool(
  {
    name: "parse_receipt",
    description: "Parse a receipt into structured line items. Provide either the raw text of a receipt or describe what's on it. The AI will structure it into items that can then be split. For image receipts, describe what you see or paste the OCR text.",
    schema: z.object({
      receiptText: z.string().describe("The text content of the receipt, or a description of items and prices"),
      merchantName: z.string().optional().describe("Name of the merchant/restaurant"),
      date: z.string().optional().describe("Date of purchase (YYYY-MM-DD)"),
      currency: z.string().default("USD").describe("Currency code"),
    }),
  },
  async ({ receiptText, merchantName, date, currency }) => {
    // Parse the receipt text into line items
    // This is a simplified parser - in production, you'd use OCR + ML
    const lines = receiptText.split("\n").filter(l => l.trim());
    const lineItems: ReceiptLineItem[] = [];

    let subtotal = 0;
    let tax = 0;
    let tip = 0;
    let total = 0;

    // Simple regex patterns for common receipt formats
    const itemPattern = /^(.+?)\s+\$?([\d,]+\.?\d*)\s*$/;
    const taxPattern = /tax/i;
    const tipPattern = /tip|gratuity/i;
    const totalPattern = /total|amount due/i;
    const subtotalPattern = /subtotal/i;

    for (const line of lines) {
      const match = line.match(itemPattern);
      if (match) {
        const description = match[1].trim();
        const price = parseFloat(match[2].replace(",", ""));

        if (taxPattern.test(description)) {
          tax = parseMoney(price, currency);
        } else if (tipPattern.test(description)) {
          tip = parseMoney(price, currency);
        } else if (totalPattern.test(description)) {
          total = parseMoney(price, currency);
        } else if (subtotalPattern.test(description)) {
          subtotal = parseMoney(price, currency);
        } else if (price > 0) {
          lineItems.push({
            description,
            quantity: 1,
            unitPrice: parseMoney(price, currency),
            totalPrice: parseMoney(price, currency),
          });
        }
      }
    }

    // Calculate subtotal if not found
    if (subtotal === 0) {
      subtotal = lineItems.reduce((sum, item) => sum + item.totalPrice, 0);
    }

    // Calculate total if not found
    if (total === 0) {
      total = subtotal + tax + tip;
    }

    const receipt = receiptStore.create({
      merchantName,
      date: date ? new Date(date) : new Date(),
      lineItems,
      subtotal,
      tax: tax || undefined,
      tip: tip || undefined,
      total,
      currency,
      rawText: receiptText,
      confidence: lineItems.length > 0 ? 0.8 : 0.5,
    });

    const itemList = lineItems.map((item, i) =>
      `  ${i + 1}. ${item.description}: ${formatMoney(item.totalPrice, currency)}`
    ).join("\n");

    return {
      content: [{
        type: "text",
        text: `**Parsed Receipt** (ID: ${receipt.id})
${merchantName ? `Merchant: ${merchantName}` : ""}
Date: ${receipt.date?.toLocaleDateString() || "Unknown"}

**Items:**
${itemList || "  No items parsed - try providing clearer item descriptions"}

Subtotal: ${formatMoney(subtotal, currency)}
${tax ? `Tax: ${formatMoney(tax, currency)}` : ""}
${tip ? `Tip: ${formatMoney(tip, currency)}` : ""}
**Total: ${formatMoney(total, currency)}**

Use \`assign_receipt_items\` to assign items to people, or \`create_expense_from_receipt\` to create an expense.`,
      }],
    };
  }
);

server.tool(
  {
    name: "add_receipt_items",
    description: "Manually add or modify items on a parsed receipt. Use this to correct parsing errors or add missing items.",
    schema: z.object({
      receiptId: z.string().describe("The receipt ID to modify"),
      items: z.array(z.object({
        description: z.string(),
        price: z.number().describe("Price in dollars (e.g., 12.99)"),
        quantity: z.number().default(1),
      })).describe("Items to add"),
      tax: z.number().optional().describe("Tax amount in dollars"),
      tip: z.number().optional().describe("Tip amount in dollars"),
    }),
  },
  async ({ receiptId, items, tax, tip }) => {
    const receipt = receiptStore.get(receiptId);
    if (!receipt) {
      return {
        content: [{
          type: "text",
          text: `Receipt ${receiptId} not found.`,
        }],
      };
    }

    const newItems: ReceiptLineItem[] = items.map(item => ({
      description: item.description,
      quantity: item.quantity,
      unitPrice: parseMoney(item.price, receipt.currency),
      totalPrice: parseMoney(item.price * item.quantity, receipt.currency),
    }));

    const allItems = [...receipt.lineItems, ...newItems];
    const subtotal = allItems.reduce((sum, i) => sum + i.totalPrice, 0);
    const newTax = tax !== undefined ? parseMoney(tax, receipt.currency) : receipt.tax;
    const newTip = tip !== undefined ? parseMoney(tip, receipt.currency) : receipt.tip;
    const total = subtotal + (newTax || 0) + (newTip || 0);

    receiptStore.update(receiptId, {
      lineItems: allItems,
      subtotal,
      tax: newTax,
      tip: newTip,
      total,
    });

    return {
      content: [{
        type: "text",
        text: `Added ${items.length} items to receipt. New total: ${formatMoney(total, receipt.currency)}`,
      }],
    };
  }
);

// ============================================================================
// EXPENSE MANAGEMENT TOOLS
// ============================================================================

server.tool(
  {
    name: "add_expense",
    description: "Add a quick expense without a receipt. Perfect for simple splits like 'I paid $50 for the Uber, split it with Jake and Sarah'. Specify who paid, the amount, and who to split with.",
    schema: z.object({
      groupId: z.string().optional().describe("Group ID (optional - will use default or create ad-hoc)"),
      groupName: z.string().optional().describe("Group name (alternative to ID)"),
      description: z.string().describe("What the expense was for"),
      amount: z.number().describe("Total amount in dollars (e.g., 45.50)"),
      currency: z.string().default("USD"),
      paidByName: z.string().describe("Name of person who paid"),
      splitWithNames: z.array(z.string()).describe("Names of people to split with (include payer if they should share the cost)"),
      splitType: z.enum(["equal", "exact", "percentage", "shares"]).default("equal"),
      splitAmounts: z.array(z.number()).optional().describe("For exact/percentage/shares splits, amounts per person in same order as splitWithNames"),
      category: z.enum(["food", "drinks", "transportation", "accommodation", "entertainment", "shopping", "groceries", "utilities", "services", "other"]).default("other"),
      date: z.string().optional().describe("Date (YYYY-MM-DD), defaults to today"),
      notes: z.string().optional(),
    }),
  },
  async ({ groupId, groupName, description, amount, currency, paidByName, splitWithNames, splitType, splitAmounts, category, date, notes }) => {
    // Find or create group
    let group = groupId ? groupStore.get(groupId) : groupName ? groupStore.getByName(groupName) : undefined;

    // If no group specified, create an ad-hoc one
    if (!group) {
      const allNames = [paidByName, ...splitWithNames.filter(n => n !== paidByName)];
      group = groupStore.create({
        name: `${paidByName}'s expenses`,
        members: allNames.map(name => ({
          personId: personStore.getOrCreate(name).id,
          joinedAt: new Date(),
        })),
        defaultCurrency: currency,
        isTrip: false,
      });
    }

    // Get or create payer
    const payer = personStore.getOrCreate(paidByName);

    // Ensure payer is in group
    groupStore.addMember(group.id, payer.id);

    // Get or create split participants and ensure they're in group
    const participants = splitWithNames.map(name => {
      const person = personStore.getOrCreate(name);
      groupStore.addMember(group!.id, person.id);
      return person;
    });

    // Calculate splits
    const totalMinor = parseMoney(amount, currency);
    let splits: ExpenseSplit[] = [];

    if (splitType === "equal") {
      const perPerson = Math.floor(totalMinor / participants.length);
      const remainder = totalMinor - (perPerson * participants.length);

      splits = participants.map((p, i) => ({
        personId: p.id,
        amount: perPerson + (i === 0 ? remainder : 0), // First person gets remainder
      }));
    } else if (splitType === "exact" && splitAmounts) {
      splits = participants.map((p, i) => ({
        personId: p.id,
        amount: parseMoney(splitAmounts[i] || 0, currency),
      }));
    } else if (splitType === "percentage" && splitAmounts) {
      splits = participants.map((p, i) => ({
        personId: p.id,
        amount: Math.round(totalMinor * ((splitAmounts[i] || 0) / 100)),
        percentage: splitAmounts[i],
      }));
    } else if (splitType === "shares" && splitAmounts) {
      const totalShares = splitAmounts.reduce((sum, s) => sum + s, 0);
      splits = participants.map((p, i) => ({
        personId: p.id,
        amount: Math.round(totalMinor * ((splitAmounts[i] || 0) / totalShares)),
        shares: splitAmounts[i],
      }));
    }

    const expense = expenseStore.create({
      groupId: group.id,
      description,
      totalAmount: totalMinor,
      currency,
      category: category as ExpenseCategory,
      paidBy: payer.id,
      splitType: splitType as SplitType,
      splits,
      date: date ? new Date(date) : new Date(),
      notes,
    });

    const splitBreakdown = splits.map(s => {
      const person = personStore.get(s.personId);
      return `${person?.name}: ${formatMoney(s.amount, currency)}`;
    }).join(", ");

    return {
      content: [{
        type: "text",
        text: `**Added expense:** ${description}
Amount: ${formatMoney(totalMinor, currency)}
Paid by: ${payer.name}
Split (${splitType}): ${splitBreakdown}
Group: ${group.name}
ID: ${expense.id}`,
      }],
    };
  }
);

server.tool(
  {
    name: "create_expense_from_receipt",
    description: "Create an expense from a previously parsed receipt. You can specify how to split it.",
    schema: z.object({
      receiptId: z.string().describe("The receipt ID"),
      groupId: z.string().optional().describe("Group ID"),
      groupName: z.string().optional().describe("Group name"),
      paidByName: z.string().describe("Name of person who paid"),
      splitWithNames: z.array(z.string()).describe("Names of people to split with"),
      splitType: z.enum(["equal", "itemized"]).default("equal"),
      itemAssignments: z.array(z.object({
        itemIndex: z.number().describe("Item index (1-based)"),
        assignedToNames: z.array(z.string()).describe("Names of people who had this item"),
      })).optional().describe("For itemized splits, who had which items"),
      includeTaxTip: z.boolean().default(true).describe("Distribute tax/tip proportionally"),
    }),
  },
  async ({ receiptId, groupId, groupName, paidByName, splitWithNames, splitType, itemAssignments, includeTaxTip }) => {
    const receipt = receiptStore.get(receiptId);
    if (!receipt) {
      return {
        content: [{
          type: "text",
          text: `Receipt ${receiptId} not found.`,
        }],
      };
    }

    // Find or create group
    let group = groupId ? groupStore.get(groupId) : groupName ? groupStore.getByName(groupName) : undefined;

    if (!group) {
      const allNames = [paidByName, ...splitWithNames.filter(n => n !== paidByName)];
      group = groupStore.create({
        name: receipt.merchantName || "Shared expense",
        members: allNames.map(name => ({
          personId: personStore.getOrCreate(name).id,
          joinedAt: new Date(),
        })),
        defaultCurrency: receipt.currency,
        isTrip: false,
      });
    }

    const payer = personStore.getOrCreate(paidByName);
    groupStore.addMember(group.id, payer.id);

    const participants = splitWithNames.map(name => {
      const person = personStore.getOrCreate(name);
      groupStore.addMember(group!.id, person.id);
      return person;
    });

    let splits: ExpenseSplit[] = [];
    const taxTipTotal = (includeTaxTip ? (receipt.tax || 0) + (receipt.tip || 0) : 0);

    if (splitType === "equal") {
      const totalToSplit = receipt.subtotal + taxTipTotal;
      const perPerson = Math.floor(totalToSplit / participants.length);
      const remainder = totalToSplit - (perPerson * participants.length);

      splits = participants.map((p, i) => ({
        personId: p.id,
        amount: perPerson + (i === 0 ? remainder : 0),
      }));
    } else if (splitType === "itemized" && itemAssignments) {
      // Calculate each person's item total
      const personTotals = new Map<string, number>();
      participants.forEach(p => personTotals.set(p.id, 0));

      for (const assignment of itemAssignments) {
        const itemIdx = assignment.itemIndex - 1;
        if (itemIdx >= 0 && itemIdx < receipt.lineItems.length) {
          const item = receipt.lineItems[itemIdx];
          const assignees = assignment.assignedToNames.map(n => personStore.getOrCreate(n));
          const perAssignee = Math.floor(item.totalPrice / assignees.length);

          for (const assignee of assignees) {
            const current = personTotals.get(assignee.id) || 0;
            personTotals.set(assignee.id, current + perAssignee);
          }
        }
      }

      // Add proportional tax/tip
      const subtotalFromItems = Array.from(personTotals.values()).reduce((sum, v) => sum + v, 0);

      splits = participants.map(p => {
        const itemTotal = personTotals.get(p.id) || 0;
        const proportion = subtotalFromItems > 0 ? itemTotal / subtotalFromItems : 1 / participants.length;
        const taxTipShare = Math.round(taxTipTotal * proportion);

        return {
          personId: p.id,
          amount: itemTotal + taxTipShare,
          items: itemAssignments
            .filter(a => a.assignedToNames.some(n => personStore.getByName(n)?.id === p.id))
            .map(a => receipt.lineItems[a.itemIndex - 1]?.description)
            .filter(Boolean),
        };
      });
    }

    const expense = expenseStore.create({
      groupId: group.id,
      description: receipt.merchantName || "Receipt expense",
      totalAmount: receipt.total,
      currency: receipt.currency,
      category: "food",
      paidBy: payer.id,
      splitType: splitType as SplitType,
      splits,
      subtotal: receipt.subtotal,
      tax: receipt.tax,
      tip: receipt.tip,
      date: receipt.date || new Date(),
      receiptId: receipt.id,
    });

    const splitBreakdown = splits.map(s => {
      const person = personStore.get(s.personId);
      return `${person?.name}: ${formatMoney(s.amount, receipt.currency)}`;
    }).join("\n  ");

    return {
      content: [{
        type: "text",
        text: `**Created expense from receipt**
${receipt.merchantName || "Unknown merchant"}
Total: ${formatMoney(receipt.total, receipt.currency)}
Paid by: ${payer.name}

Split breakdown:
  ${splitBreakdown}

Expense ID: ${expense.id}`,
      }],
    };
  }
);

server.tool(
  {
    name: "list_expenses",
    description: "List expenses for a group or person. Shows recent expenses with who paid and how it was split.",
    schema: z.object({
      groupId: z.string().optional().describe("Group ID to filter by"),
      groupName: z.string().optional().describe("Group name to filter by"),
      personName: z.string().optional().describe("Person name to filter by"),
      limit: z.number().default(10).describe("Maximum number of expenses to show"),
    }),
  },
  async ({ groupId, groupName, personName, limit }) => {
    let expenses;

    if (groupId || groupName) {
      const group = groupId ? groupStore.get(groupId) : groupStore.getByName(groupName!);
      if (!group) {
        return { content: [{ type: "text", text: "Group not found." }] };
      }
      expenses = expenseStore.getByGroup(group.id);
    } else if (personName) {
      const person = personStore.getByName(personName);
      if (!person) {
        return { content: [{ type: "text", text: `Person "${personName}" not found.` }] };
      }
      expenses = expenseStore.getByPerson(person.id);
    } else {
      expenses = expenseStore.list();
    }

    expenses = expenses.slice(0, limit);

    if (expenses.length === 0) {
      return {
        content: [{
          type: "text",
          text: "No expenses found. Use add_expense to create one.",
        }],
      };
    }

    const list = expenses.map(e => {
      const payer = personStore.get(e.paidBy);
      const group = groupStore.get(e.groupId);
      const splitInfo = e.splits.map(s => {
        const p = personStore.get(s.personId);
        return `${p?.name}: ${formatMoney(s.amount, e.currency)}`;
      }).join(", ");

      return `**${e.description}** - ${formatMoney(e.totalAmount, e.currency)}
  Paid by: ${payer?.name} | Date: ${e.date.toLocaleDateString()}
  Group: ${group?.name} | Split: ${splitInfo}
  ID: ${e.id}`;
    }).join("\n\n");

    return {
      content: [{
        type: "text",
        text: `**Expenses (${expenses.length}):**\n\n${list}`,
      }],
    };
  }
);

// ============================================================================
// BALANCE & SETTLEMENT TOOLS
// ============================================================================

server.tool(
  {
    name: "get_balances",
    description: "Get the current balance for each person in a group. Shows who has paid more than their share (is owed money) and who owes money.",
    schema: z.object({
      groupId: z.string().optional(),
      groupName: z.string().optional(),
    }),
  },
  async ({ groupId, groupName }) => {
    const group = groupId ? groupStore.get(groupId) : groupName ? groupStore.getByName(groupName) : undefined;

    if (!group) {
      return { content: [{ type: "text", text: "Group not found." }] };
    }

    const balances = calculateBalances(group.id);

    if (balances.length === 0) {
      return {
        content: [{
          type: "text",
          text: `No expenses recorded for "${group.name}" yet.`,
        }],
      };
    }

    const list = balances.map(b => {
      const status = b.netBalance > 0
        ? `is owed ${formatMoney(b.netBalance, group.defaultCurrency)}`
        : b.netBalance < 0
          ? `owes ${formatMoney(Math.abs(b.netBalance), group.defaultCurrency)}`
          : "is settled up";

      return `**${b.personName}**: ${status}
  Paid: ${formatMoney(b.totalPaid, group.defaultCurrency)} | Owes: ${formatMoney(b.totalOwed, group.defaultCurrency)}`;
    }).join("\n\n");

    return {
      content: [{
        type: "text",
        text: `**Balances for "${group.name}":**\n\n${list}`,
      }],
    };
  }
);

server.tool(
  {
    name: "get_balance_between",
    description: "Get the running balance between two specific people across all their shared groups. Useful for 'What's the tab between me and Jake?'",
    schema: z.object({
      personAName: z.string().describe("First person's name"),
      personBName: z.string().describe("Second person's name"),
    }),
  },
  async ({ personAName, personBName }) => {
    const personA = personStore.getByName(personAName);
    const personB = personStore.getByName(personBName);

    if (!personA || !personB) {
      return {
        content: [{
          type: "text",
          text: `Could not find both people. Make sure "${personAName}" and "${personBName}" exist.`,
        }],
      };
    }

    const balance = getBalanceBetween(personA.id, personB.id);

    if (!balance) {
      return {
        content: [{
          type: "text",
          text: `${personA.name} and ${personB.name} don't share any groups.`,
        }],
      };
    }

    if (balance.amount === 0) {
      return {
        content: [{
          type: "text",
          text: `${personA.name} and ${personB.name} are all squared up!`,
        }],
      };
    }

    const fromName = balance.aOwesB ? personA.name : personB.name;
    const toName = balance.aOwesB ? personB.name : personA.name;

    return {
      content: [{
        type: "text",
        text: `**${fromName}** owes **${toName}** ${formatMoney(balance.amount, balance.currency)}`,
      }],
    };
  }
);

server.tool(
  {
    name: "calculate_settlements",
    description: "Calculate the optimal way to settle all debts in a group with the minimum number of payments. This simplifies complex debt webs into direct payments.",
    schema: z.object({
      groupId: z.string().optional(),
      groupName: z.string().optional(),
    }),
  },
  async ({ groupId, groupName }) => {
    const group = groupId ? groupStore.get(groupId) : groupName ? groupStore.getByName(groupName) : undefined;

    if (!group) {
      return { content: [{ type: "text", text: "Group not found." }] };
    }

    const debts = simplifyDebts(group.id);

    if (debts.length === 0) {
      return {
        content: [{
          type: "text",
          text: `Everyone in "${group.name}" is all settled up!`,
        }],
      };
    }

    // Clear existing settlements and create new ones
    settlementStore.clearGroupSettlements(group.id);

    const settlements = debts.map(debt => {
      return settlementStore.create({
        groupId: group.id,
        from: debt.from,
        to: debt.to,
        amount: debt.amount,
        currency: debt.currency,
        status: "pending",
      });
    });

    const list = debts.map((debt, i) => {
      const fromPerson = personStore.get(debt.from);
      const toPerson = personStore.get(debt.to);
      return `${i + 1}. **${debt.fromName}** pays **${debt.toName}**: ${formatMoney(debt.amount, debt.currency)}
   Settlement ID: ${settlements[i].id}`;
    }).join("\n\n");

    return {
      content: [{
        type: "text",
        text: `**Settlements for "${group.name}"** (${debts.length} payment${debts.length > 1 ? "s" : ""} needed):\n\n${list}\n\nUse \`generate_payment_link\` to create payment links, or \`mark_settled\` when payments are complete.`,
      }],
    };
  }
);

server.tool(
  {
    name: "generate_payment_link",
    description: "Generate a Venmo or PayPal payment link for a settlement. Makes it easy to pay with one click.",
    schema: z.object({
      settlementId: z.string().optional().describe("Settlement ID"),
      fromName: z.string().optional().describe("Alternative: person who owes"),
      toName: z.string().optional().describe("Alternative: person who is owed"),
      groupName: z.string().optional().describe("Group name (used with fromName/toName)"),
      paymentMethod: z.enum(["venmo", "paypal"]).default("venmo"),
    }),
  },
  async ({ settlementId, fromName, toName, groupName, paymentMethod }) => {
    let settlement;

    if (settlementId) {
      settlement = settlementStore.get(settlementId);
    } else if (fromName && toName && groupName) {
      const from = personStore.getByName(fromName);
      const to = personStore.getByName(toName);
      const group = groupStore.getByName(groupName);

      if (from && to && group) {
        const settlements = settlementStore.getByGroup(group.id);
        settlement = settlements.find(s => s.from === from.id && s.to === to.id && s.status === "pending");
      }
    }

    if (!settlement) {
      return {
        content: [{
          type: "text",
          text: "Settlement not found. Use calculate_settlements first to generate settlements.",
        }],
      };
    }

    const from = personStore.get(settlement.from);
    const to = personStore.get(settlement.to);

    if (!from || !to) {
      return { content: [{ type: "text", text: "Could not find people for this settlement." }] };
    }

    if (paymentMethod === "venmo") {
      if (!to.venmoUsername) {
        return {
          content: [{
            type: "text",
            text: `${to.name} doesn't have a Venmo username set. Use update_person to add one.`,
          }],
        };
      }

      const group = groupStore.get(settlement.groupId);
      const note = `Settling up${group ? ` for ${group.name}` : ""} - via Ledgex`;

      const deepLink = generateVenmoLink({
        recipientUsername: to.venmoUsername,
        amount: settlement.amount,
        currency: settlement.currency,
        note,
      });

      const webLink = generateVenmoWebLink({
        recipientUsername: to.venmoUsername,
        amount: settlement.amount,
        currency: settlement.currency,
        note,
      });

      // Update settlement with payment link
      settlementStore.update(settlement.id, {
        paymentMethod: "venmo",
        paymentLink: webLink,
        status: "requested",
        requestedAt: new Date(),
      });

      return {
        content: [{
          type: "text",
          text: `**Payment Link for ${from.name} to pay ${to.name}**
Amount: ${formatMoney(settlement.amount, settlement.currency)}

**Venmo App:** ${deepLink}
**Venmo Web:** ${webLink}

Click the link to open Venmo with the payment pre-filled!`,
        }],
      };
    }

    return {
      content: [{
        type: "text",
        text: `PayPal link generation not fully implemented. Use Venmo or mark as settled manually.`,
      }],
    };
  }
);

server.tool(
  {
    name: "mark_settled",
    description: "Mark a settlement as completed. Use this after someone has paid.",
    schema: z.object({
      settlementId: z.string().optional(),
      fromName: z.string().optional(),
      toName: z.string().optional(),
      groupName: z.string().optional(),
      paymentMethod: z.enum(["venmo", "paypal", "cash", "bank_transfer", "other"]).optional(),
      notes: z.string().optional(),
    }),
  },
  async ({ settlementId, fromName, toName, groupName, paymentMethod, notes }) => {
    let settlement;

    if (settlementId) {
      settlement = settlementStore.get(settlementId);
    } else if (fromName && toName) {
      const from = personStore.getByName(fromName);
      const to = personStore.getByName(toName);

      if (from && to) {
        let settlements;
        if (groupName) {
          const group = groupStore.getByName(groupName);
          if (group) {
            settlements = settlementStore.getByGroup(group.id);
          }
        } else {
          settlements = settlementStore.list();
        }

        settlement = settlements?.find(s =>
          s.from === from.id && s.to === to.id && s.status !== "completed"
        );
      }
    }

    if (!settlement) {
      return {
        content: [{
          type: "text",
          text: "Settlement not found or already completed.",
        }],
      };
    }

    const updated = settlementStore.update(settlement.id, {
      status: "completed",
      completedAt: new Date(),
      paymentMethod: paymentMethod as any,
      notes,
    });

    const from = personStore.get(settlement.from);
    const to = personStore.get(settlement.to);

    const confirmation = generateSettlementConfirmation(
      from?.name || "Unknown",
      to?.name || "Unknown",
      settlement.amount,
      settlement.currency,
      paymentMethod || "unknown method"
    );

    return {
      content: [{
        type: "text",
        text: confirmation,
      }],
    };
  }
);

server.tool(
  {
    name: "get_pending_settlements",
    description: "Get all pending (unpaid) settlements for a person or group.",
    schema: z.object({
      personName: z.string().optional(),
      groupName: z.string().optional(),
    }),
  },
  async ({ personName, groupName }) => {
    let settlements;

    if (groupName) {
      const group = groupStore.getByName(groupName);
      if (!group) {
        return { content: [{ type: "text", text: "Group not found." }] };
      }
      settlements = settlementStore.getByGroup(group.id).filter(s => s.status === "pending");
    } else if (personName) {
      const person = personStore.getByName(personName);
      if (!person) {
        return { content: [{ type: "text", text: `Person "${personName}" not found.` }] };
      }
      settlements = settlementStore.getPendingForPerson(person.id);
    } else {
      settlements = settlementStore.list().filter(s => s.status === "pending");
    }

    if (settlements.length === 0) {
      return {
        content: [{
          type: "text",
          text: "No pending settlements found. Everyone is squared up!",
        }],
      };
    }

    const list = settlements.map(s => {
      const from = personStore.get(s.from);
      const to = personStore.get(s.to);
      const group = groupStore.get(s.groupId);

      return `**${from?.name}** owes **${to?.name}**: ${formatMoney(s.amount, s.currency)}
  Group: ${group?.name} | ID: ${s.id}`;
    }).join("\n\n");

    return {
      content: [{
        type: "text",
        text: `**Pending Settlements (${settlements.length}):**\n\n${list}`,
      }],
    };
  }
);

// ============================================================================
// REMINDER & ANALYTICS TOOLS
// ============================================================================

server.tool(
  {
    name: "generate_reminder",
    description: "Generate a friendly payment reminder message that can be sent to someone who owes money.",
    schema: z.object({
      fromName: z.string().describe("Person who owes"),
      toName: z.string().describe("Person who is owed"),
      groupName: z.string().optional(),
    }),
  },
  async ({ fromName, toName, groupName }) => {
    const from = personStore.getByName(fromName);
    const to = personStore.getByName(toName);

    if (!from || !to) {
      return {
        content: [{
          type: "text",
          text: "Could not find both people.",
        }],
      };
    }

    const balance = getBalanceBetween(from.id, to.id);

    if (!balance || balance.amount === 0) {
      return {
        content: [{
          type: "text",
          text: `${from.name} doesn't owe ${to.name} anything!`,
        }],
      };
    }

    const group = groupName ? groupStore.getByName(groupName) : undefined;

    const reminder = generateReminderMessage({
      fromName: from.name,
      toName: to.name,
      amount: balance.amount,
      currency: balance.currency,
      groupName: group?.name,
    });

    return {
      content: [{
        type: "text",
        text: `**Payment Reminder:**\n\n${reminder}`,
      }],
    };
  }
);

server.tool(
  {
    name: "get_group_summary",
    description: "Get a comprehensive summary of a group including total expenses, balances, and settlements needed.",
    schema: z.object({
      groupId: z.string().optional(),
      groupName: z.string().optional(),
    }),
  },
  async ({ groupId, groupName }) => {
    const group = groupId ? groupStore.get(groupId) : groupName ? groupStore.getByName(groupName) : undefined;

    if (!group) {
      return { content: [{ type: "text", text: "Group not found." }] };
    }

    const summary = getGroupSummary(group.id);

    if (!summary) {
      return { content: [{ type: "text", text: "Could not generate summary." }] };
    }

    const balanceList = summary.balances.map(b => {
      const status = b.netBalance > 0
        ? `+${formatMoney(b.netBalance, summary.currency)}`
        : b.netBalance < 0
          ? formatMoney(b.netBalance, summary.currency)
          : "settled";
      return `  ${b.personName}: ${status}`;
    }).join("\n");

    const debtList = summary.simplifiedDebts.length > 0
      ? summary.simplifiedDebts.map(d =>
          `  ${d.fromName} → ${d.toName}: ${formatMoney(d.amount, d.currency)}`
        ).join("\n")
      : "  Everyone is settled up!";

    return {
      content: [{
        type: "text",
        text: `**${summary.groupName} Summary**

**Stats:**
  Total Expenses: ${formatMoney(summary.totalExpenses, summary.currency)}
  Number of Expenses: ${summary.expenseCount}
  Members: ${summary.memberCount}

**Balances:**
${balanceList}

**Settlements Needed:**
${debtList}`,
      }],
    };
  }
);

// ============================================================================
// UTILITY TOOLS
// ============================================================================

server.tool(
  {
    name: "seed_demo_data",
    description: "Seed the system with demo data for testing. Creates sample people, groups, and expenses.",
    schema: z.object({}),
  },
  async () => {
    store.seed();
    const stats = store.stats();

    return {
      content: [{
        type: "text",
        text: `Seeded demo data:
- ${stats.persons} people
- ${stats.groups} groups
- ${stats.expenses} expenses

Try "list_groups" or "get_balances groupName=Roommates" to explore!`,
      }],
    };
  }
);

server.tool(
  {
    name: "clear_all_data",
    description: "Clear all data from the system. Use with caution!",
    schema: z.object({
      confirm: z.boolean().describe("Must be true to confirm deletion"),
    }),
  },
  async ({ confirm }) => {
    if (!confirm) {
      return {
        content: [{
          type: "text",
          text: "Please set confirm=true to clear all data.",
        }],
      };
    }

    store.clear();

    return {
      content: [{
        type: "text",
        text: "All data has been cleared.",
      }],
    };
  }
);

server.tool(
  {
    name: "get_stats",
    description: "Get statistics about the current state of the system.",
    schema: z.object({}),
  },
  async () => {
    const stats = store.stats();

    return {
      content: [{
        type: "text",
        text: `**Ledgex Stats:**
- People: ${stats.persons}
- Groups: ${stats.groups}
- Expenses: ${stats.expenses}
- Settlements: ${stats.settlements}
- Receipts: ${stats.receipts}`,
      }],
    };
  }
);

// ============================================================================
// PROMPTS
// ============================================================================

server.prompt(
  {
    name: "split_dinner",
    description: "Help split a dinner or restaurant bill among friends. Guides through receipt parsing, item assignment, and creating the expense.",
    schema: z.object({
      receiptText: z.string().optional().describe("The receipt text or items to split"),
      participants: z.string().optional().describe("Comma-separated names of people at the dinner"),
      payer: z.string().optional().describe("Who paid the bill"),
    }),
  },
  async ({ receiptText, participants, payer }) => {
    const participantList = participants || "the group";
    const payerName = payer || "someone";

    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `I need help splitting a dinner bill.

${receiptText ? `Here's the receipt:\n${receiptText}` : "I'll describe what we ordered."}

Participants: ${participantList}
${payer ? `Paid by: ${payerName}` : ""}

Please help me:
1. Parse the receipt items if provided
2. Ask who had which items (or if we should split equally)
3. Create the expense with the right splits
4. Show me the balances afterward`,
        },
      }],
    };
  }
);

server.prompt(
  {
    name: "start_trip",
    description: "Set up expense tracking for a trip. Creates a trip group and explains how to track expenses throughout.",
    schema: z.object({
      tripName: z.string().describe("Name of the trip (e.g., 'Vegas Weekend', 'Beach Vacation')"),
      travelers: z.string().describe("Comma-separated names of people going on the trip"),
      location: z.string().optional().describe("Trip destination"),
      startDate: z.string().optional().describe("Start date (YYYY-MM-DD)"),
      endDate: z.string().optional().describe("End date (YYYY-MM-DD)"),
    }),
  },
  async ({ tripName, travelers, location, startDate, endDate }) => {
    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `I'm going on a trip and want to track shared expenses.

Trip: ${tripName}
Who's going: ${travelers}
${location ? `Location: ${location}` : ""}
${startDate ? `Dates: ${startDate}${endDate ? ` to ${endDate}` : ""}` : ""}

Please:
1. Create a trip group for us
2. Explain how I can add expenses as we go
3. Let me know I can ask to "settle up" at the end to see who owes what`,
        },
      }],
    };
  }
);

server.prompt(
  {
    name: "settle_up",
    description: "Calculate and help execute settlements for a group. Shows who owes whom and generates payment links.",
    schema: z.object({
      groupName: z.string().describe("Name of the group to settle"),
    }),
  },
  async ({ groupName }) => {
    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `Time to settle up for "${groupName}"!

Please:
1. Show me the current balances for everyone
2. Calculate the optimal way to settle all debts
3. Generate Venmo payment links for each settlement
4. Let me mark payments as complete when they're done`,
        },
      }],
    };
  }
);

server.prompt(
  {
    name: "quick_expense",
    description: "Quickly add an expense that someone covered. Perfect for Ubers, coffees, or any shared cost.",
    schema: z.object({
      description: z.string().describe("What the expense was for"),
      amount: z.string().describe("How much it cost"),
      payer: z.string().describe("Who paid"),
      splitWith: z.string().describe("Comma-separated names to split with"),
    }),
  },
  async ({ description, amount, payer, splitWith }) => {
    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `${payer} paid $${amount} for ${description}. Split it with ${splitWith}.

Please add this expense and show me the updated balances.`,
        },
      }],
    };
  }
);

server.prompt(
  {
    name: "check_balance",
    description: "Check the running balance between you and another person, or see all balances for a group.",
    schema: z.object({
      personOrGroup: z.string().describe("Person name to check balance with, or group name to see all balances"),
      myName: z.string().optional().describe("Your name (if checking balance with a person)"),
    }),
  },
  async ({ personOrGroup, myName }) => {
    const isPersonCheck = myName !== undefined;

    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: isPersonCheck
            ? `What's the running tab between me (${myName}) and ${personOrGroup}? Show me all our shared expenses and the net balance.`
            : `Show me all the balances for the "${personOrGroup}" group. Who owes money and who is owed?`,
        },
      }],
    };
  }
);

server.prompt(
  {
    name: "parse_and_assign",
    description: "Parse a receipt and interactively assign items to people. Handles shared items and calculates fair splits.",
    schema: z.object({
      receiptText: z.string().describe("The receipt text with items and prices"),
      people: z.string().describe("Comma-separated names of people to assign items to"),
    }),
  },
  async ({ receiptText, people }) => {
    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `Here's a receipt to split:

${receiptText}

People: ${people}

Please:
1. Parse this into individual items
2. Ask me who had each item (items can be shared)
3. Calculate each person's share including proportional tax/tip
4. Create the expense with itemized splits`,
        },
      }],
    };
  }
);

server.prompt(
  {
    name: "roommates_setup",
    description: "Set up a roommate expense-sharing group for ongoing shared costs like rent, utilities, and groceries.",
    schema: z.object({
      roommates: z.string().describe("Comma-separated names of all roommates"),
      groupName: z.string().optional().describe("Name for the group (default: 'Roommates')"),
    }),
  },
  async ({ roommates, groupName }) => {
    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `I want to set up expense tracking for my roommates: ${roommates}

Group name: ${groupName || "Roommates"}

Please:
1. Create the roommate group
2. Explain how we can track shared expenses (rent, utilities, groceries, etc.)
3. Show me how to check balances and settle up periodically`,
        },
      }],
    };
  }
);

server.prompt(
  {
    name: "payment_reminder",
    description: "Generate a friendly reminder message for someone who owes you money.",
    schema: z.object({
      fromPerson: z.string().describe("Person who owes money"),
      toPerson: z.string().describe("Person who is owed"),
      groupName: z.string().optional().describe("Group name for context"),
    }),
  },
  async ({ fromPerson, toPerson, groupName }) => {
    return {
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `Generate a friendly payment reminder for ${fromPerson} to pay ${toPerson}${groupName ? ` for "${groupName}" expenses` : ""}.

Include:
1. The amount owed
2. A Venmo payment link if available
3. Keep it light and friendly!`,
        },
      }],
    };
  }
);

// ============================================================================
// SERVER STARTUP
// ============================================================================

const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;

console.log(`
╔═══════════════════════════════════════════════════════════════╗
║                     LEDGEX MCP SERVER                        ║
║                                                               ║
║  AI-powered expense splitting for groups                      ║
║                                                               ║
║  Tools available:                                             ║
║  - Receipt parsing & item assignment                          ║
║  - Quick expenses & group management                          ║
║  - Balance calculation & debt simplification                  ║
║  - Settlement generation & payment links                      ║
║                                                               ║
║  Server: http://localhost:${PORT}                               ║
║  Inspector: http://localhost:${PORT}/inspector                  ║
╚═══════════════════════════════════════════════════════════════╝
`);

server.listen(PORT);
