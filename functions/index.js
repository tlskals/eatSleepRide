const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * 🔔 실시간 알림(notifications) 문서 생성 시 수신 대상자에게 크로스플랫폼(iOS APNs + Android FCM) 푸시 발송
 */
exports.sendPushOnNotification = onDocumentCreated(
  {
    document: "notifications/{docId}",
    region: "asia-northeast3", // 서울 리전
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data) return;

    const senderUid = data.senderUid || "";
    const title = data.title || "같이 타요 알림";
    const body = data.body || "";
    const postId = data.postId || "";
    const type = data.type || "notification";
    let targetUids = Array.isArray(data.targetUids) ? data.targetUids : [];

    console.log(`[Push Trigger] 알림 수신: title="${title}", body="${body}", senderUid="${senderUid}", targetUids=${JSON.stringify(targetUids)}`);

    // 수신자 UID 목록이 비어있는 경우 (1) postId가 있으면 gatherings 문서에서 참가자/방장 UID 직접 조회
    if (targetUids.length === 0 && postId) {
      try {
        const gatheringDoc = await db.collection("gatherings").doc(postId).get();
        if (gatheringDoc.exists) {
          const gData = gatheringDoc.data();
          const pUids = Array.isArray(gData?.participantUids) ? gData.participantUids : [];
          const aUid = gData?.authorUid || "";
          for (const uid of pUids) {
            if (uid && !targetUids.includes(uid)) targetUids.push(uid);
          }
          if (aUid && !targetUids.includes(aUid)) targetUids.push(aUid);
        }
      } catch (err) {
        console.error("[Push Trigger] gatherings 조회 실패:", err);
      }
    }

    // (2) 닉네임 목록(targetParticipants)이 있는 경우 유저 닉네임으로 역조회
    if (targetUids.length === 0) {
      const targetParticipants = Array.isArray(data.targetParticipants)
        ? data.targetParticipants
        : data.targetAuthor
        ? [data.targetAuthor]
        : [];

      for (const nick of targetParticipants) {
        if (!nick) continue;
        const userQuery = await db.collection("users").where("nickname", "==", nick).get();
        userQuery.forEach((doc) => {
          if (doc.id !== senderUid && !targetUids.includes(doc.id)) {
            targetUids.push(doc.id);
          }
        });
      }
    }

    // 발신자 본인은 수신 대상에서 제외
    targetUids = targetUids.filter((uid) => uid && uid !== senderUid);

    if (targetUids.length === 0) {
      console.log("[Push Trigger] 발송 대상자 UID가 없습니다. (발신자 본인이거나 대상 없음)");
      return;
    }

    // 각 대상자의 FCM 토큰 조회
    const tokens = [];
    const tokenUidMap = new Map();

    for (const uid of targetUids) {
      const userDoc = await db.collection("users").doc(uid).get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        const fcmToken = userData?.fcmToken;
        if (fcmToken && typeof fcmToken === "string" && fcmToken.length > 10) {
          tokens.push(fcmToken);
          tokenUidMap.set(fcmToken, uid);
        }
      }
    }

    if (tokens.length === 0) {
      console.log("[Push Trigger] 유효한 FCM 토큰을 가진 수신자가 없습니다.");
      return;
    }

    console.log(`[Push Trigger] 총 ${tokens.length}개의 기기로 푸시 발송 시작`);

    // 🚀 iOS (APNs) + Android (FCM) 멀티플랫폼 최적화 페이로드 구성
    const message = {
      tokens: tokens,
      notification: {
        title: title,
        body: body,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "eatsleepride_high_channel",
          sound: "default",
          defaultSound: true,
          defaultVibrateTimings: true,
          notificationCount: 1,
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
          "apns-topic": "com.tlskals.eatsleepride",
        },
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            badge: 1,
            sound: "default",
            "content-available": 1,
            "mutable-content": 1,
          },
        },
      },
      data: {
        postId: String(postId),
        type: String(type),
        title: String(title),
        body: String(body),
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`[Push Result] 성공: ${response.successCount}건, 실패: ${response.failureCount}건`);

      // 만료되거나 유효하지 않은 토큰 정리
      if (response.failureCount > 0) {
        const failedTokens = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const error = resp.error;
            const token = tokens[idx];
            console.error(`[Push Error] 토큰 발송 실패: ${token} - ${error?.message}`);
            if (
              error?.code === "messaging/invalid-registration-token" ||
              error?.code === "messaging/registration-token-not-registered"
            ) {
              failedTokens.push(token);
            }
          }
        });

        for (const token of failedTokens) {
          const uid = tokenUidMap.get(token);
          if (uid) {
            await db.collection("users").doc(uid).set(
              { fcmToken: admin.firestore.FieldValue.delete() },
              { merge: true }
            );
            console.log(`[Push Cleanup] 만료된 토큰 삭제 완료: user=${uid}`);
          }
        }
      }
    } catch (err) {
      console.error("[Push Fatal Error] 푸시 전송 중 치명적 오류 발생:", err);
    }
  }
);
