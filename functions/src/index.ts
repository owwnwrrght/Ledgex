import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import fetch from "node-fetch";
import { randomUUID } from "crypto";

admin.initializeApp();

const dynamicLinkKey = defineSecret("FDL_API_KEY");

interface FirebaseDynamicLinkResponse {
  shortLink: string;
  previewLink?: string;
}

interface PersonDoc {
  id?: string;
  name?: string;
  hasCompletedExpenses?: boolean;
  totalPaid?: number;
  totalOwed?: number;
  isManuallyAdded?: boolean;
  firebaseUID?: string;
}

interface ExpenseDoc {
  id?: string;
  description?: string;
  amount?: number;
  baseCurrency?: string;
  createdBy?: string;
  participantIDs?: string[];
}

interface TripDoc {
  name?: string;
  code?: string;
  baseCurrency?: string;
  people?: PersonDoc[];
  expenses?: ExpenseDoc[];
  phase?: "setup" | "active" | "completed";
}

type TokenRecord = { token: string; userId: string };

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const messaging = admin.messaging();

export const createTripInvite = onRequest({
  region: "us-central1",
  secrets: [dynamicLinkKey],
}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const tripCode = (req.body?.tripCode ?? req.body?.groupCode)?.toString().trim().toUpperCase();
  const tripName = (req.body?.tripName ?? req.body?.groupName)?.toString().trim() ?? "Ledgex group";

  if (!tripCode) {
    res.status(400).json({ error: "groupCode is required" });
    return;
  }

  const baseLink = new URL("https://splyt-4801c.web.app/join");
  baseLink.searchParams.set("type", "group");
  baseLink.searchParams.set("code", tripCode);

  const payload = {
    dynamicLinkInfo: {
      domainUriPrefix: "https://splyt.page.link",
      link: baseLink.toString(),
      iosInfo: {
        bundleId: "com.OwenWright.Ledgex-ios",
      },
      socialMetaTagInfo: {
        socialTitle: `Join ${tripName}`,
        socialDescription: "Open Ledgex to track and split shared expenses.",
      },
    },
    suffix: { option: "SHORT" },
  };

  const apiKey = dynamicLinkKey.value();
  if (!apiKey) {
    res.status(500).json({ error: "FDL API key not configured" });
    return;
  }

  const response = await fetch(
    `https://firebasedynamiclinks.googleapis.com/v1/shortLinks?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
  );

  if (!response.ok) {
    const text = await response.text();
    logger.error("Failed to create dynamic link", { status: response.status, text });
    res.status(500).json({ error: "Failed to create dynamic link" });
    return;
  }

  const json = (await response.json()) as FirebaseDynamicLinkResponse;
  logger.info("Generated group invite", { shortLink: json.shortLink, tripCode });

  res.json(json);
});

export const publicStats = onRequest({
  region: "us-central1",
}, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    res.status(204).send("");
    return;
  }

  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const now = admin.firestore.Timestamp.now();
    const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(
      now.toMillis() - 30 * 24 * 60 * 60 * 1000,
    );

    const tripsCountSnap = await db.collection("trips").count().get();
    const recentTripsSnap = await db
      .collection("trips")
      .where("createdDate", ">=", thirtyDaysAgo)
      .count()
      .get();
    const activeTripsSnap = await db
      .collection("trips")
      .where("phase", "==", "active")
      .count()
      .get();

    res.set("Access-Control-Allow-Origin", "*");
    res.set("Cache-Control", "public, max-age=300");
    res.json({
      trips: tripsCountSnap.data().count ?? 0,
      recentTrips: recentTripsSnap.data().count ?? 0,
      activeTrips: activeTripsSnap.data().count ?? 0,
    });
  } catch (error) {
    logger.error("Failed to fetch public stats", error as Error);
    res.status(500).json({ error: "internal_error" });
  }
});

export const joinTrip = onRequest({
  region: "us-central1",
}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const authHeader = req.headers.authorization ?? req.headers.Authorization;
    if (typeof authHeader !== "string" || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "unauthorized", message: "Missing or invalid authorization token." });
      return;
    }

    const idToken = authHeader.slice("Bearer ".length);
    let decodedToken: admin.auth.DecodedIdToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(idToken);
    } catch (error) {
      logger.warn("joinTrip: invalid ID token", error as Error);
      res.status(401).json({ error: "unauthorized", message: "Invalid authorization token." });
      return;
    }

    const tripCode = (req.body?.code ?? req.body?.tripCode ?? req.body?.groupCode)
      ?.toString()
      .trim()
      .toUpperCase();

    if (!tripCode) {
      res.status(400).json({ error: "invalid_code", message: "Group code is required." });
      return;
    }

    const tripSnapshot = await db.collection("trips").where("code", "==", tripCode).limit(1).get();
    if (tripSnapshot.empty) {
      res.status(404).json({ error: "group_not_found", message: "We couldn't find a group with that code." });
      return;
    }

    const tripDoc = tripSnapshot.docs[0];
    const tripRef = tripDoc.ref;

    const profileRef = db.collection("users").doc(decodedToken.uid);
    const profileDoc = await profileRef.get();
    const profileData = profileDoc.data() ?? {};

    const personId = (profileData.id as string | undefined) ?? randomUUID();
    const personName =
      (profileData.name as string | undefined)?.trim() ??
      decodedToken.name ??
      "Ledgex Member";

    const transactionResult = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(tripRef);
      if (!snapshot.exists) {
        throw new Error("missing_trip");
      }

      const tripData = snapshot.data() as TripDoc & { peopleIDs?: string[] };
      const people = Array.isArray(tripData.people) ? tripData.people : [];
      const peopleIDs = Array.isArray(tripData.peopleIDs) ? tripData.peopleIDs : [];

      const alreadyMember =
        peopleIDs.includes(decodedToken.uid) ||
        people.some((person) => person.id === personId || person.firebaseUID === decodedToken.uid);

      if (!alreadyMember) {
        const newPerson: PersonDoc = {
          id: personId,
          name: personName,
          totalPaid: 0,
          totalOwed: 0,
          isManuallyAdded: false,
          hasCompletedExpenses: false,
          firebaseUID: decodedToken.uid,
        };

        transaction.update(tripRef, {
          people: FieldValue.arrayUnion(newPerson),
          peopleIDs: FieldValue.arrayUnion(decodedToken.uid),
          lastModified: FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(tripRef, {
          lastModified: FieldValue.serverTimestamp(),
        });
      }

      return {
        alreadyMember,
        tripName: tripData.name ?? "Group",
      };
    });

    const profileUpdates: Record<string, unknown> = {
      id: personId,
      firebaseUID: decodedToken.uid,
      name: personName,
      tripCodes: FieldValue.arrayUnion(tripCode),
      lastSynced: FieldValue.serverTimestamp(),
    };

    if (!profileDoc.exists) {
      profileUpdates["dateCreated"] = FieldValue.serverTimestamp();
      profileUpdates["preferredCurrency"] = "USD";
    }

    await profileRef.set(profileUpdates, { merge: true });

    res.json({
      tripId: tripRef.id,
      tripCode,
      tripName: transactionResult.tripName,
      alreadyMember: transactionResult.alreadyMember,
    });
  } catch (error) {
    logger.error("Failed to join trip", error as Error);
    res.status(500).json({ error: "internal_error", message: "Something went wrong while joining the group." });
  }
});

export const onTripUpdated = onDocumentUpdated("trips/{tripId}", async (event) => {
  const beforeData = event.data?.before.data() as TripDoc | undefined;
  const afterData = event.data?.after.data() as TripDoc | undefined;
  if (!afterData) {
    return;
  }

  const tripId = event.params.tripId as string;
  const tasks: Array<Promise<void>> = [];

  // Check if trip phase changed from setup to active
  const phaseChanged = beforeData?.phase === "setup" && afterData.phase === "active";
  if (phaseChanged) {
    tasks.push(handleTripStarted(afterData, tripId));
  }

  const newExpenses = detectNewExpenses(beforeData?.expenses, afterData.expenses);
  if (newExpenses.length > 0) {
    tasks.push(handleNewExpenses(newExpenses, afterData, tripId));
  }

  const newPeople = detectNewPeople(beforeData?.people, afterData.people);
  if (newPeople.length > 0) {
    tasks.push(handleNewMembers(newPeople, afterData, tripId));
  }

  const wasReady = isTripReadyToSettle(beforeData?.people);
  const isReady = isTripReadyToSettle(afterData.people);
  if (!wasReady && isReady) {
    tasks.push(handleReadyToSettle(afterData, tripId));
  }

  await Promise.all(tasks);
});

function detectNewExpenses(before: ExpenseDoc[] | undefined, after: ExpenseDoc[] | undefined): ExpenseDoc[] {
  const beforeIds = new Set((before ?? []).map((expense) => expense.id));
  return (after ?? []).filter((expense) => expense.id && !beforeIds.has(expense.id));
}

function detectNewPeople(before: PersonDoc[] | undefined, after: PersonDoc[] | undefined): PersonDoc[] {
  const beforeIds = new Set((before ?? []).map((person) => person.id));
  return (after ?? []).filter((person) => person.id && !beforeIds.has(person.id));
}

async function handleNewExpenses(expenses: ExpenseDoc[], trip: TripDoc, tripId: string): Promise<void> {
  const people = trip.people ?? [];
  const baseCurrency = trip.baseCurrency ?? "USD";
  const tripName = trip.name ?? "Group";
  const tripCode = trip.code ?? "";

  for (const expense of expenses) {
    if (!expense.id) {
      continue;
    }

    const creator = expense.createdBy ?? null;
    const participantIDs = Array.isArray(expense.participantIDs) && expense.participantIDs.length > 0
      ? expense.participantIDs
      : people.map((person) => person.id).filter((id): id is string => Boolean(id));

    const recipients = participantIDs
      .filter((id): id is string => Boolean(id) && id !== creator);

    const tokens = await fetchTokens(recipients);
    if (!tokens.length) {
      continue;
    }

    const amountValue = typeof expense.amount === "number" ? expense.amount : 0;
    const amountText = formatCurrency(amountValue, baseCurrency);

    await sendMulticast(tokens, {
      title: `New expense in ${tripName}`,
      body: `${expense.description ?? "Expense"} – ${amountText}`,
    }, {
      type: "newExpense",
      tripId,
      tripCode,
      expenseId: expense.id,
    });
  }
}

async function handleNewMembers(members: PersonDoc[], trip: TripDoc, tripId: string): Promise<void> {
  const people = trip.people ?? [];
  const tripName = trip.name ?? "Group";
  const tripCode = trip.code ?? "";

  for (const member of members) {
    if (!member.id) {
      continue;
    }
    const recipients = people
      .map((person) => person.id)
      .filter((id): id is string => Boolean(id) && id !== member.id);

    const tokens = await fetchTokens(recipients);
    if (!tokens.length) {
      continue;
    }

    await sendMulticast(tokens, {
      title: `New member joined ${tripName}`,
      body: `${member.name ?? "Someone"} just joined this trip`,
    }, {
      type: "newMember",
      tripId,
      tripCode,
      memberId: member.id,
    });
  }
}

async function handleTripStarted(trip: TripDoc, tripId: string): Promise<void> {
  const people = trip.people ?? [];
  const tripName = trip.name ?? "Group";
  const tripCode = trip.code ?? "";

  const recipients = people
    .map((person) => person.id)
    .filter((id): id is string => Boolean(id));

  const tokens = await fetchTokens(recipients);
  if (!tokens.length) {
    return;
  }

  await sendMulticast(tokens, {
    title: `${tripName} has started!`,
    body: "You can now start adding expenses to the trip",
  }, {
    type: "tripStarted",
    tripId,
    tripCode,
  });
}

async function handleReadyToSettle(trip: TripDoc, tripId: string): Promise<void> {
  const people = trip.people ?? [];
  const tripName = trip.name ?? "Group";
  const tripCode = trip.code ?? "";

  const recipients = people
    .map((person) => person.id)
    .filter((id): id is string => Boolean(id));

  const tokens = await fetchTokens(recipients);
  if (!tokens.length) {
    return;
  }

  await sendMulticast(tokens, {
    title: `${tripName} is ready to settle`,
    body: "Everyone finished adding expenses. Time to split!",
  }, {
    type: "readyToSettle",
    tripId,
    tripCode,
  });
}

async function fetchTokens(userIds: string[]): Promise<TokenRecord[]> {
  if (!userIds.length) {
    return [];
  }

  const snapshots = await Promise.all(
    userIds.map((id) => db.collection("users").doc(id).get()),
  );

  const tokens: TokenRecord[] = [];
  snapshots.forEach((snapshot, index) => {
    if (!snapshot.exists) {
      return;
    }
    const data = snapshot.data();
    const storedTokens: unknown = data?.tokens;
    if (Array.isArray(storedTokens)) {
      storedTokens.forEach((token) => {
        if (typeof token === "string") {
          tokens.push({ token, userId: userIds[index] });
        }
      });
    }
  });

  const deduped = new Map(tokens.map((record) => [record.token, record]));
  return Array.from(deduped.values());
}

async function sendMulticast(tokens: TokenRecord[], notification: { title: string; body: string }, data: Record<string, string>): Promise<void> {
  if (!tokens.length) {
    return;
  }

  const response = await messaging.sendEachForMulticast({
    tokens: tokens.map((record) => record.token),
    notification,
    data,
  });

  const invalid: TokenRecord[] = [];
  response.responses.forEach((resp, index) => {
    if (!resp.success) {
      const errorCode = resp.error?.code ?? "";
      if (errorCode === "messaging/registration-token-not-registered" ||
          errorCode === "messaging/invalid-registration-token") {
        invalid.push(tokens[index]);
      }
    }
  });

  if (invalid.length) {
    await Promise.all(invalid.map(({ token, userId }) =>
      db.collection("users").doc(userId).update({
        tokens: FieldValue.arrayRemove(token),
      })
    ));
  }
}

function formatCurrency(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency,
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(amount);
  } catch (error) {
    logger.warn("Failed to format currency", { error, currency, amount });
    return amount.toFixed(2);
  }
}

function isTripReadyToSettle(people: PersonDoc[] | undefined): boolean {
  if (!people || !people.length) {
    return false;
  }
  return people
    .filter((person) => Boolean(person.id))
    .every((person) => Boolean(person.hasCompletedExpenses));
}
