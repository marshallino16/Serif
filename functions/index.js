const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { google } = require("googleapis");

admin.initializeApp();
const db = admin.firestore();
const dns = require("dns").promises;

// Personal/freemail domains — skip BIMI lookup for these
const PERSONAL_DOMAINS = new Set([
  "gmail.com", "googlemail.com",
  "yahoo.com", "yahoo.fr", "yahoo.co.uk", "yahoo.co.jp",
  "outlook.com", "outlook.fr", "live.com", "live.fr",
  "hotmail.com", "hotmail.fr", "hotmail.co.uk",
  "icloud.com", "me.com", "mac.com",
  "protonmail.com", "proton.me", "pm.me",
  "aol.com", "wanadoo.fr", "orange.fr", "sfr.fr", "free.fr",
  "laposte.net", "bbox.fr", "numericable.fr",
]);

// Resolve BIMI logo URL via DNS TXT record
async function resolveBIMI(domain) {
  if (!domain || PERSONAL_DOMAINS.has(domain.toLowerCase())) return null;
  try {
    const records = await dns.resolveTxt(`default._bimi.${domain}`);
    for (const record of records) {
      const txt = record.join("");
      if (txt.includes("v=BIMI1")) {
        const match = txt.match(/l=([^\s;]+)/);
        if (match) return match[1];
      }
    }
  } catch (_) {}
  return null;
}

// Config param (set via firebase functions:config or .env)
const GMAIL_CLIENT_ID = defineString("GMAIL_CLIENT_ID");

// Refresh access token using PKCE flow (no client_secret needed for iOS)
async function getAccessToken(refreshToken) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GMAIL_CLIENT_ID.value(),
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Token refresh failed (${response.status}): ${text}`);
  }
  const data = await response.json();
  return data.access_token;
}

// ─── 1. Gmail Push Handler (Pub/Sub → FCM) ─────────────────────────────────

exports.gmailPush = onRequest(async (req, res) => {
  try {
    console.log("[gmailPush] Raw body:", JSON.stringify(req.body));

    const message = req.body.message;
    if (!message || !message.data) {
      console.log("[gmailPush] No message.data found");
      return res.status(400).send("No Pub/Sub message");
    }

    const decoded = JSON.parse(
      Buffer.from(message.data, "base64").toString()
    );
    console.log("[gmailPush] Decoded:", JSON.stringify(decoded));

    const { emailAddress, historyId } = decoded;
    if (!emailAddress) return res.status(400).send("No email address");
    console.log("[gmailPush] email:", emailAddress, "historyId:", historyId);

    // Find user in Firestore
    const userRef = db.collection("users").doc(emailAddress);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      return res.status(200).send("Unknown user, skipping");
    }

    const userData = userDoc.data();
    console.log("[gmailPush] Firestore data:", JSON.stringify({
      devices: userData.devices?.length,
      lastHistoryId: userData.historyId,
      hasRefreshToken: !!userData.refreshToken,
      notifyCategories: userData.notifyCategories
    }));
    const { devices, historyId: lastHistoryId, refreshToken, notifyCategories } = userData;

    if (!devices || devices.length === 0) {
      return res.status(200).send("No devices registered");
    }

    if (!refreshToken) {
      return res.status(200).send("No refresh token, skipping");
    }

    // Categories the user wants notifications for (empty/missing = all)
    const allowedCategories = notifyCategories || [];

    // Get fresh access token
    let accessToken;
    try {
      accessToken = await getAccessToken(refreshToken);
    } catch (err) {
      console.error("Token refresh failed:", err.message);
      return res.status(200).send("Token refresh failed");
    }

    // Query Gmail History API for new messages
    const gmail = google.gmail({ version: "v1" });
    let newMessages = [];
    try {
      const history = await gmail.users.history.list({
        userId: "me",
        startHistoryId: lastHistoryId || historyId,
        historyTypes: ["messageAdded"],
        labelId: "INBOX",
        access_token: accessToken,
      });
      const entries = history.data.history || [];
      for (const entry of entries) {
        if (entry.messagesAdded) {
          for (const added of entry.messagesAdded) {
            if (added.message.labelIds &&
                added.message.labelIds.includes("INBOX")) {
              newMessages.push(added.message);
            }
          }
        }
      }
    } catch (err) {
      if (err.code === 404) {
        await userRef.update({ historyId });
        return res.status(200).send("History expired, reset");
      }
      throw err;
    }

    console.log("[gmailPush] newMessages count:", newMessages.length);

    if (newMessages.length === 0) {
      await userRef.update({ historyId });
      return res.status(200).send("No new inbox messages");
    }

    // Multi-message vs single-message notification
    if (newMessages.length > 1) {
      // Get real unread count for badge
      let unreadCount = newMessages.length;
      try {
        const inboxLabel = await gmail.users.labels.get({
          userId: "me", id: "INBOX", access_token: accessToken,
        });
        unreadCount = inboxLabel.data.messagesUnread || newMessages.length;
      } catch (_) {}

      const tokens = devices.map((d) => d.token);
      const fcmMessage = {
        notification: {
          title: "Serif",
          body: `${newMessages.length} new emails`,
        },
        data: { emailAddress, type: "new_emails", count: String(newMessages.length) },
        apns: {
          payload: { aps: { sound: "default", badge: unreadCount } },
        },
      };
      console.log("[gmailPush] Sending multi-message notification:", newMessages.length);
      const fcmResponse = await admin.messaging().sendEachForMulticast({ tokens, ...fcmMessage });
      await userRef.update({ historyId });
      return res.status(200).send(`Sent ${fcmResponse.successCount} multi notifications`);
    }

    // Single message: rich notification with details
    const latestMsgId = newMessages[0].id;
    let from = "New email";
    let fromEmail = "";
    let subject = "";
    let snippet = "";
    let date = "";
    let threadId = "";
    let msgLabels = [];
    try {
      const msg = await gmail.users.messages.get({
        userId: "me",
        id: latestMsgId,
        format: "metadata",
        metadataHeaders: ["Subject", "From", "Date"],
        access_token: accessToken,
      });
      const headers = msg.data.payload.headers || [];
      const rawFrom = headers.find((h) => h.name === "From")?.value || "New email";
      subject = headers.find((h) => h.name === "Subject")?.value || "";
      date = headers.find((h) => h.name === "Date")?.value || "";
      snippet = (msg.data.snippet || "")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&amp;/g, "&")
        .replace(/&#39;/g, "'")
        .replace(/&quot;/g, '"');
      msgLabels = msg.data.labelIds || [];
      threadId = msg.data.threadId || "";

      // Parse "Name <email>" format
      const emailMatch = rawFrom.match(/<([^>]+)>/);
      fromEmail = emailMatch ? emailMatch[1] : rawFrom;
      const nameMatch = rawFrom.match(/^"?([^"<]+)"?\s*</);
      from = nameMatch ? nameMatch[1].trim() : rawFrom;
    } catch (_) {
      // Fallback to generic notification
    }

    // Build Gravatar URL for sender avatar
    const crypto = require("crypto");
    const emailHash = crypto.createHash("md5")
      .update(fromEmail.trim().toLowerCase())
      .digest("hex");
    const avatarUrl = `https://www.gravatar.com/avatar/${emailHash}?s=200&d=404`;

    // Resolve sender's Google Contact photo via People API
    let contactPhotoUrl = "";
    try {
      const searchRes = await fetch(
        `https://people.googleapis.com/v1/otherContacts:search?query=${encodeURIComponent(fromEmail)}&readMask=photos&pageSize=1`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
      if (searchRes.ok) {
        const searchData = await searchRes.json();
        const photo = searchData.results?.[0]?.person?.photos?.find((p) => !p.default);
        if (photo?.url) contactPhotoUrl = photo.url;
      }
      // Also try saved contacts if otherContacts didn't find it
      if (!contactPhotoUrl) {
        const connRes = await fetch(
          `https://people.googleapis.com/v1/people:searchContacts?query=${encodeURIComponent(fromEmail)}&readMask=photos&pageSize=1`,
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
        if (connRes.ok) {
          const connData = await connRes.json();
          const photo = connData.results?.[0]?.person?.photos?.find((p) => !p.default);
          if (photo?.url) contactPhotoUrl = photo.url;
        }
      }
    } catch (_) {}

    // Resolve BIMI logo URL for organizational senders
    const senderDomain = fromEmail.includes("@") ? fromEmail.split("@")[1].toLowerCase() : "";
    let bimiUrl = "";
    try {
      const resolved = await resolveBIMI(senderDomain);
      if (resolved) bimiUrl = resolved;
    } catch (_) {}

    // Logo.dev URL for company logos (returns 404 for unknown domains)
    const logoDevUrl = senderDomain && !PERSONAL_DOMAINS.has(senderDomain)
      ? `https://img.logo.dev/${senderDomain}?token=pk_FOE8O0atTB6nht6rIwyp1Q&size=200&format=png` : "";

    // Filter by user's notification category preferences
    if (allowedCategories.length > 0) {
      const categoryLabels = msgLabels.filter((l) => l.startsWith("CATEGORY_"));
      if (categoryLabels.length > 0 &&
          !categoryLabels.some((l) => allowedCategories.includes(l))) {
        await userRef.update({ historyId });
        return res.status(200).send("Message category not in user preferences");
      }
    }

    // Get real unread count from Gmail
    let unreadCount = 1;
    try {
      const profile = await gmail.users.getProfile({
        userId: "me",
        access_token: accessToken,
      });
      // Gmail labels endpoint gives exact INBOX unread count
      const inboxLabel = await gmail.users.labels.get({
        userId: "me",
        id: "INBOX",
        access_token: accessToken,
      });
      unreadCount = inboxLabel.data.messagesUnread || 1;
    } catch (_) {
      // Fallback to 1
    }

    // Send FCM to all registered devices
    const tokens = devices.map((d) => d.token);
    const fcmMessage = {
      notification: { title: subject || "New email", body: from },
      data: {
        messageId: latestMsgId,
        threadId,
        emailAddress,
        type: "new_email",
        senderName: from,
        senderEmail: fromEmail,
        subject,
        snippet,
        date,
        avatarUrl,
        bimiUrl,
        contactPhotoUrl,
        logoDevUrl,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: unreadCount,
            "mutable-content": 1,
            category: "com.serif.email",
          },
        },
      },
    };

    console.log("[gmailPush] Sending FCM to tokens:", tokens.map(t => t.substring(0, 20) + "..."));
    console.log("[gmailPush] Notification:", JSON.stringify(fcmMessage.notification));

    const fcmResponse = await admin.messaging().sendEachForMulticast({
      tokens,
      ...fcmMessage,
    });

    console.log("[gmailPush] FCM result: success=" + fcmResponse.successCount + " failure=" + fcmResponse.failureCount);
    fcmResponse.responses.forEach((r, i) => {
      if (r.error) console.error("[gmailPush] FCM error for token " + i + ":", r.error.code, r.error.message);
      else console.log("[gmailPush] FCM success for token " + i + ": messageId=" + r.messageId);
    });

    // Remove stale tokens
    const staleTokens = [];
    fcmResponse.responses.forEach((r, i) => {
      if (r.error &&
          (r.error.code === "messaging/registration-token-not-registered" ||
           r.error.code === "messaging/invalid-registration-token")) {
        staleTokens.push(tokens[i]);
      }
    });
    if (staleTokens.length > 0) {
      const updatedDevices = devices.filter(
        (d) => !staleTokens.includes(d.token)
      );
      await userRef.update({ devices: updatedDevices });
    }

    await userRef.update({ historyId });
    res.status(200).send(`Sent ${fcmResponse.successCount} notifications`);
  } catch (err) {
    console.error("gmailPush error:", err);
    res.status(500).send("Internal error");
  }
});

// ─── 2. Renew Gmail watch() — runs every 6 days ────────────────────────────

exports.renewWatch = onSchedule("every 144 hours", async () => {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  const topicName = `projects/${projectId}/topics/gmail-push`;
  const snapshot = await db.collection("users").get();

  for (const doc of snapshot.docs) {
    const { refreshToken } = doc.data();
    if (!refreshToken) continue;

    try {
      const accessToken = await getAccessToken(refreshToken);
      const gmail = google.gmail({ version: "v1" });
      const watchRes = await gmail.users.watch({
        userId: "me",
        requestBody: { topicName, labelIds: ["INBOX"] },
        access_token: accessToken,
      });
      if (watchRes.data.historyId) {
        await doc.ref.update({ historyId: watchRes.data.historyId });
      }
      console.log(`Renewed watch for ${doc.id}`);
    } catch (err) {
      console.error(`Failed to renew watch for ${doc.id}:`, err.message);
    }
  }
});
