import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { randomUUID } from "crypto";
import * as functions from "firebase-functions";

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

type TokenRecord = { token: string; docId: string; personId?: string };

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

export const forceDeleteAccount = onRequest({
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
      logger.warn("forceDeleteAccount: invalid ID token", error as Error);
      res.status(401).json({ error: "unauthorized", message: "Invalid authorization token." });
      return;
    }

    const uid = decodedToken.uid;

    // Delete primary user document if it exists
    try {
      const directDoc = await db.collection("users").doc(uid).get();
      if (directDoc.exists) {
        await directDoc.ref.delete();
      } else {
        const byUidSnapshot = await db.collection("users").where("firebaseUID", "==", uid).limit(1).get();
        if (!byUidSnapshot.empty) {
          await byUidSnapshot.docs[0].ref.delete();
        }
      }
    } catch (error) {
      logger.warn("forceDeleteAccount: failed to remove user document", error as Error);
    }

    try {
      await admin.auth().deleteUser(uid);
      logger.info("forceDeleteAccount: deleted auth user", { uid });
    } catch (error) {
      logger.error("forceDeleteAccount: failed to delete auth user", error as Error);
      res.status(500).json({ error: "delete_failed", message: "Failed to delete account. Try again later." });
      return;
    }

    res.json({ status: "deleted" });
  } catch (error) {
    logger.error("forceDeleteAccount: unexpected error", error as Error);
    res.status(500).json({ error: "internal", message: "Unexpected error while deleting account." });
  }
});



import axios from "axios";

type ParsedReceiptItem = {
  name?: string;
  quantity?: number;
  price?: number;
  total?: number;
};

type ParsedReceipt = {
  merchantName?: string | null;
  currencyCode?: string | null;
  subtotal?: number | null;
  tax?: number | null;
  tip?: number | null;
  total?: number | null;
  items?: ParsedReceiptItem[];
  rawText?: string | null;
};

export const processReceiptImage = functions
  .region("us-central1")
  .runWith({ secrets: ["OPENAI_API_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be signed in to scan receipts.",
      );
    }

    const base64Payload = typeof (data as { image?: unknown })?.image === "string"
      ? ((data as { image?: unknown }).image as string).trim()
      : undefined;

    if (!base64Payload) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The function must be called with an 'image' argument.",
      );
    }

    const resolvedOpenAiKey = process.env.OPENAI_API_KEY;
    if (!resolvedOpenAiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "OpenAI API key not configured on the server.",
      );
    }

    const normalizedImage = normalizeBase64Image(base64Payload);
    const approxSizeBytes = Math.ceil((normalizedImage.length * 3) / 4);
    if (approxSizeBytes > 8_000_000) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Receipt image is too large. Please choose a smaller photo.",
      );
    }

    let parsedReceipt: ParsedReceipt = {};
    try {
      const systemPrompt = [
        "You are an expert receipt parser that extracts structured data from receipt images.",
        "Analyze the receipt image carefully and extract ALL individual items/purchases visible on the receipt.",
        "Return a JSON object with the following structure:",
        "- merchantName: string (name of the store/restaurant, if visible)",
        "- currencyCode: string (3-letter ISO code like USD, EUR, GBP, etc. if detectable from currency symbols)",
        "- subtotal: number (subtotal amount before tax/tip if shown separately)",
        "- tax: number (tax amount if shown, otherwise 0)",
        "- tip: number (tip/gratuity amount if shown, otherwise 0)",
        "- total: number (final total amount)",
        "- items: array of objects, each with:",
        "  * name: string (item description/name)",
        "  * quantity: number (default to 1 if not specified)",
        "  * price: number (unit price per item)",
        "  * total: number (line total = price × quantity, if different from price)",
        "- rawText: string (cleaned text of key receipt lines for reference)",
        "",
        "IMPORTANT RULES:",
        "1. Extract EVERY item from the receipt, not just a sample",
        "2. Numbers should be pure decimals with NO currency symbols (e.g., 12.99 not $12.99)",
        "3. If quantity is not specified, use 1",
        "4. Be flexible with receipt formats - they vary widely",
        "5. If you can't find specific fields (like tax/tip), set them to 0",
        "6. Focus on accuracy - every item matters for splitting bills",
        "7. If the receipt is in a language other than English, translate item names to English",
        "",
        "Return ONLY valid JSON, no other text.",
      ].join(" ");

      const openAiResponse = await axios.post(
        "https://api.openai.com/v1/chat/completions",
        {
          model: "gpt-4o",
          temperature: 0,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: systemPrompt },
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: "Please analyze this receipt image and extract all items and totals. Make sure to capture every single item on the receipt.",
                },
                {
                  type: "image_url",
                  image_url: {
                    url: `data:image/jpeg;base64,${normalizedImage}`,
                    detail: "high",
                  },
                },
              ],
            },
          ],
        },
        {
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${resolvedOpenAiKey}`,
          },
          timeout: 30_000,
        },
      );

      const content = openAiResponse.data?.choices?.[0]?.message?.content;
      if (typeof content !== "string") {
        logger.error("processReceiptImage: OpenAI response missing content", {
          response: JSON.stringify(openAiResponse.data),
        });
        throw new Error("OpenAI response missing content.");
      }

      logger.info("processReceiptImage: Received OpenAI response", {
        contentLength: content.length,
      });

      const candidate = JSON.parse(content) as ParsedReceipt;
      parsedReceipt = {
        merchantName: typeof candidate.merchantName === "string" ? candidate.merchantName : null,
        currencyCode: typeof candidate.currencyCode === "string" ? candidate.currencyCode.toUpperCase() : null,
        subtotal: coerceNumber(candidate.subtotal),
        tax: coerceNumber(candidate.tax),
        tip: coerceNumber(candidate.tip),
        total: coerceNumber(candidate.total),
        items: sanitizeItems(candidate.items),
        rawText: typeof candidate.rawText === "string" ? candidate.rawText : null,
      };

      logger.info("processReceiptImage: Successfully parsed receipt", {
        merchantName: parsedReceipt.merchantName,
        itemCount: parsedReceipt.items?.length ?? 0,
        total: parsedReceipt.total,
      });
    } catch (error) {
      const axiosError = error as any;

      // Log detailed error information
      if (axiosError.response) {
        logger.error("processReceiptImage: OpenAI API error", {
          status: axiosError.response.status,
          statusText: axiosError.response.statusText,
          data: JSON.stringify(axiosError.response.data),
        });

        // Provide more specific error messages
        if (axiosError.response.status === 401) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "OpenAI API key is invalid. Please contact support.",
          );
        } else if (axiosError.response.status === 429) {
          throw new functions.https.HttpsError(
            "resource-exhausted",
            "Too many requests. Please try again in a moment.",
          );
        }
      } else if (axiosError.request) {
        logger.error("processReceiptImage: Network error", {
          message: axiosError.message,
        });
        throw new functions.https.HttpsError(
          "unavailable",
          "Could not reach OpenAI service. Please check your internet connection.",
        );
      } else {
        logger.error("processReceiptImage: Parsing error", {
          message: axiosError.message,
          stack: axiosError.stack,
        });
      }

      throw new functions.https.HttpsError(
        "internal",
        "Failed to interpret the receipt. Please ensure the image is clear and try again.",
      );
    }

    return {
      rawText: parsedReceipt.rawText ?? null,
      merchantName: parsedReceipt.merchantName,
      currencyCode: parsedReceipt.currencyCode,
      subtotal: parsedReceipt.subtotal,
      tax: parsedReceipt.tax,
      tip: parsedReceipt.tip,
      total: parsedReceipt.total,
      items: parsedReceipt.items,
    };
  });

function normalizeBase64Image(base64: string): string {
  const trimmed = base64.replace(/^data:image\/[a-zA-Z]+;base64,/, "").replace(/\s+/g, "");
  return trimmed;
}

function coerceNumber(value: unknown): number | null {
  const numeric = typeof value === "string" ? Number(value) : value;
  if (typeof numeric !== "number" || Number.isNaN(numeric) || !Number.isFinite(numeric)) {
    return null;
  }
  return Number(numeric.toFixed(2));
}

function sanitizeItems(items: unknown): Array<Required<ParsedReceiptItem>> {
  if (!Array.isArray(items)) {
    return [];
  }

  const sanitized: Array<Required<ParsedReceiptItem>> = [];
  for (const entry of items.slice(0, 50)) {
    if (typeof entry !== "object" || entry === null) {
      continue;
    }
    const parsedEntry = entry as ParsedReceiptItem;
    const name = typeof parsedEntry.name === "string" ? parsedEntry.name.trim() : "";

    if (!name) {
      continue;
    }

    const quantity = coerceQuantity(parsedEntry.quantity);
    const price = coerceNumber(parsedEntry.price) ?? 0;

    let lineTotal = coerceNumber(parsedEntry.total);
    if (lineTotal === null && price && quantity) {
      lineTotal = Number((price * quantity).toFixed(2));
    }

    sanitized.push({
      name,
      quantity,
      price,
      total: lineTotal ?? price,
    });
  }

  return sanitized;
}

function coerceQuantity(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return Math.max(1, Math.round(value));
  }

  if (typeof value === "string") {
    const numeric = Number(value);
    if (Number.isFinite(numeric) && numeric > 0) {
      return Math.max(1, Math.round(numeric));
    }
  }

  return 1;
}

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

    const tokens = await fetchTokens(people, recipients);
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

    const tokens = await fetchTokens(people, recipients);
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

  const tokens = await fetchTokens(people, recipients);
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

  const tokens = await fetchTokens(people, recipients);
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

async function fetchTokens(people: PersonDoc[], personIds: string[]): Promise<TokenRecord[]> {
  const uniqueIds = Array.from(new Set(personIds.filter((id): id is string => Boolean(id))));
  if (!uniqueIds.length) {
    return [];
  }

  const personIndex = new Map(
    people
      .filter((person): person is PersonDoc & { id: string } => typeof person.id === "string" && person.id.length > 0)
      .map((person) => [person.id, person]),
  );

  const docIds = new Set<string>();
  uniqueIds.forEach((id) => {
    docIds.add(id);
    const person = personIndex.get(id);
    if (person?.firebaseUID) {
      docIds.add(person.firebaseUID);
    }
  });

  if (!docIds.size) {
    return [];
  }

  const snapshots = await Promise.all(
    Array.from(docIds).map((docId) => db.collection("users").doc(docId).get()),
  );

  const tokens: TokenRecord[] = [];
  const targetIds = new Set(uniqueIds);

  snapshots.forEach((snapshot) => {
    if (!snapshot.exists) {
      return;
    }

    const data = snapshot.data();
    const storedTokens: unknown = data?.tokens;
    if (!Array.isArray(storedTokens) || !storedTokens.length) {
      return;
    }

    const profileId = typeof data?.id === "string" ? data.id : undefined;
    const firebaseUID = typeof data?.firebaseUID === "string" ? data.firebaseUID : undefined;
    const matchesTarget =
      (profileId && targetIds.has(profileId)) ||
      (firebaseUID && targetIds.has(firebaseUID)) ||
      targetIds.has(snapshot.id);

    if (!matchesTarget) {
      return;
    }

    storedTokens.forEach((token) => {
      if (typeof token === "string" && token.trim().length) {
        tokens.push({
          token,
          docId: snapshot.id,
          personId: profileId ?? firebaseUID ?? snapshot.id,
        });
      }
    });
  });

  const deduped = new Map(tokens.map((record) => [record.token, record]));
  return Array.from(deduped.values());
}

async function sendMulticast(tokens: TokenRecord[], notification: { title: string; body: string }, data: Record<string, string>): Promise<void> {
  if (!tokens.length) {
    return;
  }

  logger.info(`Sending multicast notification to ${tokens.length} tokens`, { data });

  const response = await messaging.sendEachForMulticast({
    tokens: tokens.map((record) => record.token),
    notification,
    data,
  });

  const invalid: TokenRecord[] = [];
  let successCount = 0;
  let failureCount = 0;

  response.responses.forEach((resp, index) => {
    if (resp.success) {
      successCount++;
      logger.info(`Successfully sent message to token: ${tokens[index].token}`, { messageId: resp.messageId });
    } else {
      failureCount++;
      const errorCode = resp.error?.code ?? "";
      logger.warn(`Failed to send message to token: ${tokens[index].token}`, { error: resp.error });
      if (errorCode === "messaging/registration-token-not-registered" ||
          errorCode === "messaging/invalid-registration-token") {
        invalid.push(tokens[index]);
      }
    }
  });

  logger.info(`Multicast notification summary: ${successCount} success, ${failureCount} failure`);

  if (invalid.length) {
    logger.info(`Removing ${invalid.length} invalid tokens`);
    await Promise.all(invalid.map(async ({ token, docId }) => {
      try {
        await db.collection("users").doc(docId).update({
          tokens: FieldValue.arrayRemove(token),
        });
      } catch (error) {
        logger.warn("Failed to remove invalid token", { docId, token, error });
      }
    }));
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

export const onTripUpdated = onDocumentUpdated("trips/{tripId}", async (event) => {
  const beforeData = event.data?.before.data() as TripDoc | undefined;
  const afterData = event.data?.after.data() as TripDoc | undefined;
  const tripId = event.params.tripId;

  if (!beforeData || !afterData) {
    logger.info("Trip data is missing, skipping notifications.");
    return;
  }

  // Detect new expenses
  const newExpenses = detectNewExpenses(beforeData.expenses, afterData.expenses);
  if (newExpenses.length > 0) {
    logger.info(`Detected ${newExpenses.length} new expenses for trip ${tripId}`);
    await handleNewExpenses(newExpenses, afterData, tripId);
  }

  // Detect new members
  const newMembers = detectNewPeople(beforeData.people, afterData.people);
  if (newMembers.length > 0) {
    logger.info(`Detected ${newMembers.length} new members for trip ${tripId}`);
    await handleNewMembers(newMembers, afterData, tripId);
  }

  // Detect trip start
  if (beforeData.phase === "setup" && afterData.phase === "active") {
    logger.info(`Trip ${tripId} has started`);
    await handleTripStarted(afterData, tripId);
  }

  // Detect ready to settle
  const beforeIsReady = isTripReadyToSettle(beforeData.people);
  const afterIsReady = isTripReadyToSettle(afterData.people);
  if (!beforeIsReady && afterIsReady) {
    logger.info(`Trip ${tripId} is ready to settle`);
    await handleReadyToSettle(afterData, tripId);
  }
});
