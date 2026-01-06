# Ledgex MCP Server

An MCP (Model Context Protocol) server for AI-powered expense splitting. Built as an extension of the [Ledgex](https://github.com/owwnwrrght/Ledgex) bill-splitting app.

## Overview

This MCP server enables AI agents to handle the entire expense-splitting workflow through natural conversation:

- "Split this receipt with my roommates, I had the pasta and we shared the appetizer"
- "What's the running tab between me and Jake?"
- "We're going to Vegas next weekend — track all our expenses and settle at the end"

## Features

### Core Capabilities
- **Receipt Parsing**: Parse receipts (text) into structured line items
- **Flexible Splitting**: Equal, exact amounts, percentage-based, share-based, or itemized splits
- **Item Assignment**: Assign specific items to specific people, including shared items
- **Balance Tracking**: Track running balances across groups over time
- **Settlement Generation**: Calculate optimal settlements with minimal transactions
- **Payment Links**: Generate Venmo deep links for one-click payments

### Group/Social Features
- **Persistent Groups**: Roommates, regular dinner crews, etc.
- **Trip Mode**: Track everything for a trip and settle at the end
- **Quick Expenses**: Add expenses without receipts (someone covered the Uber)
- **Debt Simplification**: If A owes B $10 and B owes A $5, just show A owes B $5

### Quality of Life
- **Smart Reminders**: Generate friendly payment reminder messages
- **Group Summaries**: Comprehensive overview of group finances
- **Running Tabs**: Check balance between any two people

## Quick Start

```bash
# Install dependencies
npm install

# Start development server with hot reload
npm run dev

# Server runs at http://localhost:3000
# Inspector UI at http://localhost:3000/inspector
```

## Available Tools

### People Management

| Tool | Description |
|------|-------------|
| `create_person` | Add a new person with optional Venmo username |
| `list_people` | List all people in the system |
| `update_person` | Update someone's details (Venmo, email, etc.) |

### Group Management

| Tool | Description |
|------|-------------|
| `create_group` | Create an expense-sharing group (roommates, trips, etc.) |
| `list_groups` | List all groups with expense summaries |
| `add_group_member` | Add someone to an existing group |

### Receipt & Expense

| Tool | Description |
|------|-------------|
| `parse_receipt` | Parse receipt text into structured line items |
| `add_receipt_items` | Manually add/correct items on a receipt |
| `add_expense` | Quick expense without receipt |
| `create_expense_from_receipt` | Create expense from parsed receipt with splits |
| `list_expenses` | View expenses for a group or person |

### Balances & Settlements

| Tool | Description |
|------|-------------|
| `get_balances` | See who owes what in a group |
| `get_balance_between` | Running tab between two people |
| `calculate_settlements` | Optimal settlement calculation |
| `generate_payment_link` | Create Venmo payment link |
| `mark_settled` | Mark a settlement as paid |
| `get_pending_settlements` | View outstanding payments |

### Utilities

| Tool | Description |
|------|-------------|
| `generate_reminder` | Create friendly payment reminder |
| `get_group_summary` | Comprehensive group overview |
| `seed_demo_data` | Load sample data for testing |
| `get_stats` | System statistics |

## Example Workflows

### Basic Expense Split

```
User: "I paid $45 for lunch, split it with Jake and Sarah"

Agent uses: add_expense
  - description: "Lunch"
  - amount: 45
  - paidByName: "Me"
  - splitWithNames: ["Me", "Jake", "Sarah"]
  - splitType: "equal"
```

### Receipt with Item Assignment

```
User: "Split this receipt. I had the burger, Jake had the salad, we shared the appetizer"

Agent uses: parse_receipt → create_expense_from_receipt
  - splitType: "itemized"
  - itemAssignments: [
      { itemIndex: 1, assignedToNames: ["Me"] },        // Burger
      { itemIndex: 2, assignedToNames: ["Jake"] },     // Salad
      { itemIndex: 3, assignedToNames: ["Me", "Jake"] } // Shared appetizer
    ]
```

### Trip Tracking

```
User: "We're going to Vegas this weekend with Mike and Lisa"

Agent uses: create_group
  - name: "Vegas Trip 2024"
  - memberNames: ["Me", "Mike", "Lisa"]
  - isTrip: true
  - tripLocation: "Las Vegas"
  - tripStartDate: "2024-01-15"
  - tripEndDate: "2024-01-18"
```

### Settling Up

```
User: "Calculate how we should settle up for the Vegas trip"

Agent uses: calculate_settlements
  → Returns simplified debts (e.g., "Mike pays Lisa $45, You pay Mike $20")

User: "Generate a Venmo link for me to pay Mike"

Agent uses: generate_payment_link
  → Returns Venmo deep link with amount pre-filled
```

## Architecture

```
ledgex-mcp-server/
├── index.ts                 # MCP server with all tools
├── src/
│   ├── models/
│   │   └── types.ts         # TypeScript interfaces
│   ├── store/
│   │   └── store.ts         # In-memory data store
│   └── utils/
│       ├── settlements.ts   # Balance & settlement calculations
│       └── payments.ts      # Payment link generation
├── package.json
└── tsconfig.json
```

### Data Models

- **Person**: Name, email, Venmo username, PayPal email
- **Group**: Name, members, currency, trip details
- **Expense**: Description, amount, payer, splits, category
- **Settlement**: From, to, amount, status, payment link
- **ParsedReceipt**: Line items, tax, tip, totals

### Settlement Algorithm

Uses a greedy algorithm for debt simplification:
1. Calculate net balance for each person
2. Separate creditors (owed money) and debtors (owe money)
3. Match largest creditor with largest debtor
4. Repeat until all balanced

This minimizes the number of transactions needed to settle all debts.

## Development

```bash
# Development with hot reload
npm run dev

# Production build
npm run build

# Run production server
npm start
```

## Testing with Inspector

1. Start the server: `npm run dev`
2. Open: http://localhost:3000/inspector
3. Try these flows:
   - `seed_demo_data` → `list_groups` → `get_balances groupName=Roommates`
   - `create_group` → `add_expense` → `calculate_settlements`
   - `parse_receipt` → `create_expense_from_receipt`

## Environment Variables

```bash
PORT=3000        # Server port (default: 3000)
MCP_URL=...      # Base URL for the server
```

## Future Enhancements

- [ ] Persistent storage (SQLite/PostgreSQL)
- [ ] Image receipt parsing with OCR
- [ ] Multi-currency support with exchange rates
- [ ] PayPal payment link generation
- [ ] Recurring expenses
- [ ] Spending analytics and patterns
- [ ] Integration with Ledgex iOS app

## Built With

- [mcp-use](https://mcp-use.com) - MCP server framework
- [Zod](https://zod.dev) - Schema validation
- [TypeScript](https://www.typescriptlang.org/)

## License

MIT

---

Built for [mcp-use](https://mcp-use.com) by Owen Wright
