/**
 * Ledgex MCP Server - In-Memory Store
 *
 * Provides CRUD operations for all domain entities.
 * Data persists only during server runtime.
 *
 * In production, this would be replaced with a real database adapter.
 */

import {
  Person,
  PersonId,
  Group,
  GroupId,
  Expense,
  ExpenseId,
  Settlement,
  SettlementId,
  ParsedReceipt,
  ReceiptId,
  GroupMember,
} from '../models/types.js';

// ============================================================================
// Store State
// ============================================================================

interface StoreState {
  persons: Map<PersonId, Person>;
  groups: Map<GroupId, Group>;
  expenses: Map<ExpenseId, Expense>;
  settlements: Map<SettlementId, Settlement>;
  receipts: Map<ReceiptId, ParsedReceipt>;
}

const state: StoreState = {
  persons: new Map(),
  groups: new Map(),
  expenses: new Map(),
  settlements: new Map(),
  receipts: new Map(),
};

// ============================================================================
// ID Generation
// ============================================================================

function generateId(prefix: string): string {
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).substring(2, 8);
  return `${prefix}_${timestamp}${random}`;
}

// ============================================================================
// Person Operations
// ============================================================================

export const personStore = {
  create(data: Omit<Person, 'id' | 'createdAt'>): Person {
    const person: Person = {
      id: generateId('person'),
      createdAt: new Date(),
      ...data,
    };
    state.persons.set(person.id, person);
    return person;
  },

  get(id: PersonId): Person | undefined {
    return state.persons.get(id);
  },

  getByName(name: string): Person | undefined {
    for (const person of state.persons.values()) {
      if (person.name.toLowerCase() === name.toLowerCase()) {
        return person;
      }
    }
    return undefined;
  },

  getOrCreate(name: string): Person {
    const existing = this.getByName(name);
    if (existing) return existing;
    return this.create({ name });
  },

  update(id: PersonId, data: Partial<Person>): Person | undefined {
    const person = state.persons.get(id);
    if (!person) return undefined;
    const updated = { ...person, ...data };
    state.persons.set(id, updated);
    return updated;
  },

  delete(id: PersonId): boolean {
    return state.persons.delete(id);
  },

  list(): Person[] {
    return Array.from(state.persons.values());
  },

  findByVenmo(username: string): Person | undefined {
    for (const person of state.persons.values()) {
      if (person.venmoUsername?.toLowerCase() === username.toLowerCase()) {
        return person;
      }
    }
    return undefined;
  },
};

// ============================================================================
// Group Operations
// ============================================================================

export const groupStore = {
  create(data: Omit<Group, 'id' | 'createdAt' | 'updatedAt'>): Group {
    const group: Group = {
      id: generateId('group'),
      createdAt: new Date(),
      updatedAt: new Date(),
      ...data,
    };
    state.groups.set(group.id, group);
    return group;
  },

  get(id: GroupId): Group | undefined {
    return state.groups.get(id);
  },

  getByName(name: string): Group | undefined {
    for (const group of state.groups.values()) {
      if (group.name.toLowerCase() === name.toLowerCase()) {
        return group;
      }
    }
    return undefined;
  },

  update(id: GroupId, data: Partial<Group>): Group | undefined {
    const group = state.groups.get(id);
    if (!group) return undefined;
    const updated = { ...group, ...data, updatedAt: new Date() };
    state.groups.set(id, updated);
    return updated;
  },

  delete(id: GroupId): boolean {
    // Also delete associated expenses and settlements
    for (const expense of state.expenses.values()) {
      if (expense.groupId === id) {
        state.expenses.delete(expense.id);
      }
    }
    for (const settlement of state.settlements.values()) {
      if (settlement.groupId === id) {
        state.settlements.delete(settlement.id);
      }
    }
    return state.groups.delete(id);
  },

  list(): Group[] {
    return Array.from(state.groups.values());
  },

  addMember(groupId: GroupId, personId: PersonId, nickname?: string): Group | undefined {
    const group = state.groups.get(groupId);
    if (!group) return undefined;

    // Check if already a member
    if (group.members.some(m => m.personId === personId)) {
      return group;
    }

    const member: GroupMember = {
      personId,
      nickname,
      joinedAt: new Date(),
    };

    const updated: Group = {
      ...group,
      members: [...group.members, member],
      updatedAt: new Date(),
    };
    state.groups.set(groupId, updated);
    return updated;
  },

  removeMember(groupId: GroupId, personId: PersonId): Group | undefined {
    const group = state.groups.get(groupId);
    if (!group) return undefined;

    const updated: Group = {
      ...group,
      members: group.members.filter(m => m.personId !== personId),
      updatedAt: new Date(),
    };
    state.groups.set(groupId, updated);
    return updated;
  },

  getGroupsForPerson(personId: PersonId): Group[] {
    return Array.from(state.groups.values()).filter(group =>
      group.members.some(m => m.personId === personId)
    );
  },

  getActiveTrips(): Group[] {
    const now = new Date();
    return Array.from(state.groups.values()).filter(group =>
      group.isTrip &&
      group.tripStartDate &&
      group.tripStartDate <= now &&
      (!group.tripEndDate || group.tripEndDate >= now)
    );
  },
};

// ============================================================================
// Expense Operations
// ============================================================================

export const expenseStore = {
  create(data: Omit<Expense, 'id' | 'createdAt' | 'updatedAt'>): Expense {
    const expense: Expense = {
      id: generateId('expense'),
      createdAt: new Date(),
      updatedAt: new Date(),
      ...data,
    };
    state.expenses.set(expense.id, expense);
    return expense;
  },

  get(id: ExpenseId): Expense | undefined {
    return state.expenses.get(id);
  },

  update(id: ExpenseId, data: Partial<Expense>): Expense | undefined {
    const expense = state.expenses.get(id);
    if (!expense) return undefined;
    const updated = { ...expense, ...data, updatedAt: new Date() };
    state.expenses.set(id, updated);
    return updated;
  },

  delete(id: ExpenseId): boolean {
    return state.expenses.delete(id);
  },

  list(): Expense[] {
    return Array.from(state.expenses.values());
  },

  getByGroup(groupId: GroupId): Expense[] {
    return Array.from(state.expenses.values())
      .filter(e => e.groupId === groupId)
      .sort((a, b) => b.date.getTime() - a.date.getTime());
  },

  getByPerson(personId: PersonId): Expense[] {
    return Array.from(state.expenses.values()).filter(
      e => e.paidBy === personId || e.splits.some(s => s.personId === personId)
    );
  },

  getByDateRange(groupId: GroupId, start: Date, end: Date): Expense[] {
    return this.getByGroup(groupId).filter(
      e => e.date >= start && e.date <= end
    );
  },

  getTotalForGroup(groupId: GroupId): number {
    return this.getByGroup(groupId).reduce((sum, e) => sum + e.totalAmount, 0);
  },
};

// ============================================================================
// Settlement Operations
// ============================================================================

export const settlementStore = {
  create(data: Omit<Settlement, 'id' | 'createdAt' | 'updatedAt'>): Settlement {
    const settlement: Settlement = {
      id: generateId('settlement'),
      createdAt: new Date(),
      updatedAt: new Date(),
      ...data,
    };
    state.settlements.set(settlement.id, settlement);
    return settlement;
  },

  get(id: SettlementId): Settlement | undefined {
    return state.settlements.get(id);
  },

  update(id: SettlementId, data: Partial<Settlement>): Settlement | undefined {
    const settlement = state.settlements.get(id);
    if (!settlement) return undefined;
    const updated = { ...settlement, ...data, updatedAt: new Date() };
    state.settlements.set(id, updated);
    return updated;
  },

  delete(id: SettlementId): boolean {
    return state.settlements.delete(id);
  },

  list(): Settlement[] {
    return Array.from(state.settlements.values());
  },

  getByGroup(groupId: GroupId): Settlement[] {
    return Array.from(state.settlements.values())
      .filter(s => s.groupId === groupId)
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  },

  getPendingForPerson(personId: PersonId): Settlement[] {
    return Array.from(state.settlements.values()).filter(
      s => (s.from === personId || s.to === personId) && s.status === 'pending'
    );
  },

  markCompleted(id: SettlementId, method?: string): Settlement | undefined {
    return this.update(id, {
      status: 'completed',
      completedAt: new Date(),
      paymentMethod: method as any,
    });
  },

  clearGroupSettlements(groupId: GroupId): void {
    for (const settlement of state.settlements.values()) {
      if (settlement.groupId === groupId) {
        state.settlements.delete(settlement.id);
      }
    }
  },
};

// ============================================================================
// Receipt Operations
// ============================================================================

export const receiptStore = {
  create(data: Omit<ParsedReceipt, 'id' | 'createdAt'>): ParsedReceipt {
    const receipt: ParsedReceipt = {
      id: generateId('receipt'),
      createdAt: new Date(),
      ...data,
    };
    state.receipts.set(receipt.id, receipt);
    return receipt;
  },

  get(id: ReceiptId): ParsedReceipt | undefined {
    return state.receipts.get(id);
  },

  update(id: ReceiptId, data: Partial<ParsedReceipt>): ParsedReceipt | undefined {
    const receipt = state.receipts.get(id);
    if (!receipt) return undefined;
    const updated = { ...receipt, ...data };
    state.receipts.set(id, updated);
    return updated;
  },

  delete(id: ReceiptId): boolean {
    return state.receipts.delete(id);
  },

  list(): ParsedReceipt[] {
    return Array.from(state.receipts.values());
  },
};

// ============================================================================
// Store Utilities
// ============================================================================

export const store = {
  // Clear all data (useful for testing)
  clear(): void {
    state.persons.clear();
    state.groups.clear();
    state.expenses.clear();
    state.settlements.clear();
    state.receipts.clear();
  },

  // Get store statistics
  stats(): {
    persons: number;
    groups: number;
    expenses: number;
    settlements: number;
    receipts: number;
  } {
    return {
      persons: state.persons.size,
      groups: state.groups.size,
      expenses: state.expenses.size,
      settlements: state.settlements.size,
      receipts: state.receipts.size,
    };
  },

  // Seed with sample data (for demos)
  seed(): void {
    // Create some people
    const alice = personStore.create({ name: 'Alice', venmoUsername: 'alice-demo' });
    const bob = personStore.create({ name: 'Bob', venmoUsername: 'bob-demo' });
    const charlie = personStore.create({ name: 'Charlie' });

    // Create a group
    const group = groupStore.create({
      name: 'Roommates',
      description: 'Monthly shared expenses',
      members: [
        { personId: alice.id, joinedAt: new Date() },
        { personId: bob.id, joinedAt: new Date() },
        { personId: charlie.id, joinedAt: new Date() },
      ],
      defaultCurrency: 'USD',
      isTrip: false,
    });

    // Add some expenses
    expenseStore.create({
      groupId: group.id,
      description: 'Groceries',
      totalAmount: 7500, // $75.00
      currency: 'USD',
      category: 'groceries',
      paidBy: alice.id,
      splitType: 'equal',
      splits: [
        { personId: alice.id, amount: 2500 },
        { personId: bob.id, amount: 2500 },
        { personId: charlie.id, amount: 2500 },
      ],
      date: new Date(),
    });

    expenseStore.create({
      groupId: group.id,
      description: 'Internet Bill',
      totalAmount: 9000, // $90.00
      currency: 'USD',
      category: 'utilities',
      paidBy: bob.id,
      splitType: 'equal',
      splits: [
        { personId: alice.id, amount: 3000 },
        { personId: bob.id, amount: 3000 },
        { personId: charlie.id, amount: 3000 },
      ],
      date: new Date(),
    });
  },
};
