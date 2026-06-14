import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions";
import * as logger from "firebase-functions/logger";

admin.initializeApp();
setGlobalOptions({ maxInstances: 10, region: "europe-west1" });

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Στέλνει FCM σε χρήστη.
 */
async function sendToUser(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
): Promise<void> {
  const userDoc = await db.collection("users").doc(uid).get();
  const tokens: string[] = userDoc.data()?.fcmTokens ?? [];
  if (tokens.length === 0) {
    const single = userDoc.data()?.fcmToken;
    if (typeof single === "string" && single.length > 0) tokens.push(single);
  }
  if (tokens.length === 0) {
    logger.info(`No FCM tokens for user ${uid}`);
    return;
  }

  const payload = {
    notification: { title, body },
    data,
    android: {
      priority: "high" as const,
      notification: {
        channelId: "shareit_messages",
        sound: "default",
      },
    },
  };

  for (const token of tokens) {
    try {
      await messaging.send({ token, ...payload });
    } catch (err) {
      logger.error(`Send to ${token} failed`, err);
    }
  }
}

/**
 * 1. Νέο μήνυμα στο chat → notify receiver.
 */
export const onNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{msgId}",
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;

    const chatId = event.params.chatId;
    const senderId = msg.senderId as string;
    const text = (msg.text as string) ?? "📷 Νέο μήνυμα";

    const chatDoc = await db.collection("chats").doc(chatId).get();
    const participants = (chatDoc.data()?.participants as string[]) ?? [];
    const receiverId = participants.find((p) => p !== senderId);
    if (!receiverId) return;

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderName =
      senderDoc.data()?.firstName ?? senderDoc.data()?.fullName ?? "Νέο μήνυμα";

    await sendToUser(receiverId, senderName, text, {
      type: "chat",
      chatId,
    });
  }
);

/**
 * 2. Νέα ειδοποίηση (friend request, like, comment, deal) → push.
 */
export const onNewNotification = onDocumentCreated(
  "notifications/{notifId}",
  async (event) => {
    const n = event.data?.data();
    if (!n) return;

    const targetUid = n.targetUid as string;
    const title = (n.title as string) ?? "ShareIt";
    const body = (n.body as string) ?? "";
    const type = (n.type as string) ?? "general";

    await sendToUser(targetUid, title, body, {
      type,
      notifId: event.params.notifId,
    });
  }
);

/**
 * 3. Νέο deal proposal → notify receiver.
 */
export const onNewDeal = onDocumentCreated(
  "deals/{dealId}",
  async (event) => {
    const deal = event.data?.data();
    if (!deal) return;

    const proposerUid = deal.proposerUid as string;
    const user1 = deal.user1Uid as string;
    const user2 = deal.user2Uid as string;
    const receiverId = proposerUid === user1 ? user2 : user1;

    const proposerDoc = await db.collection("users").doc(proposerUid).get();
    const proposerName =
      proposerDoc.data()?.firstName ?? "Κάποιος";

    await sendToUser(
      receiverId,
      "🤝 Νέα πρόταση deal",
      `Ο/Η ${proposerName} σου έστειλε πρόταση deal`,
      { type: "deal", dealId: event.params.dealId }
    );
  }
);

/**
 * 4. Νέο σχόλιο σε user post → notify post author.
 */
export const onNewPostComment = onDocumentCreated(
  "userPosts/{postId}/comments/{commentId}",
  async (event) => {
    const comment = event.data?.data();
    if (!comment) return;

    const postId = event.params.postId;
    const authorUid = comment.authorUid as string;
    const text = (comment.text as string) ?? "";

    const postDoc = await db.collection("userPosts").doc(postId).get();
    const postAuthorUid = postDoc.data()?.authorUid as string;
    if (!postAuthorUid || postAuthorUid === authorUid) return;

    const commenterName = (comment.authorName as string) ?? "Κάποιος";

    await sendToUser(
      postAuthorUid,
      `💬 ${commenterName}`,
      text.length > 80 ? text.substring(0, 80) + "..." : text,
      { type: "post_comment", postId }
    );
  }
);

/**
 * 5. Νέο friend request → notify.
 */
export const onNewFriendRequest = onDocumentCreated(
  "friendRequests/{reqId}",
  async (event) => {
    const req = event.data?.data();
    if (!req) return;

    const fromUid = req.fromUid as string;
    const toUid = req.toUid as string;

    const fromDoc = await db.collection("users").doc(fromUid).get();
    const fromName = fromDoc.data()?.firstName ?? "Κάποιος";

    await sendToUser(
      toUid,
      "👋 Νέο αίτημα φιλίας",
      `Ο/Η ${fromName} θέλει να γίνετε φίλοι`,
      { type: "friend_request", fromUid }
    );
  }
);
