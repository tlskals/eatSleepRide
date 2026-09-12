import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

// 백그라운드 메시지 핸들러 (최상위 함수여야 함)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 [FCM Background] 수신: ${message.messageId} / ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static NotificationService get instance => _instance;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  bool _isInitialized = false;

  // 알림 클릭 시 콜백 등록용
  Function(String? payload)? onNotificationTap;

  /// 🚀 알림 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      // 1. 백그라운드 핸들러 등록
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (e) {
        debugPrint('🔔 [FCM] onBackgroundMessage skip: $e');
      }

      // 2. 로컬 알림 플러그인 초기화
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('🔔 [LocalNotification] 터치됨: ${response.payload}');
          onNotificationTap?.call(response.payload);
        },
      );

      // 🍎 iOS 명시적 알림 권한 획득
      try {
        final iosPlugin = _localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          await iosPlugin.requestPermissions(alert: true, badge: true, sound: true);
        }
      } catch (e) {
        debugPrint('🔔 [iOS Permissions Error]: $e');
      }

      // 3. Android 고우선순위 알림 채널 생성
      const androidChannel = AndroidNotificationChannel(
        'eatsleepride_high_channel',
        '같이타요 실시간 알림',
        description: '동행 참여 신청 및 채팅 메시지 실시간 알림을 제공합니다.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(androidChannel);
      }

      // 4. 비동기로 푸시 권한 및 FCM 토큰 획득 (앱 실행 블로킹 방지)
      unawaited(() async {
        try {
          final settings = await _fcm.requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          ).timeout(const Duration(seconds: 4));

          debugPrint('🔔 [FCM] 권한 상태: ${settings.authorizationStatus}');

          await _fcm.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );

          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
            String? apnsToken = await _fcm.getAPNSToken();
            int retry = 0;
            while (apnsToken == null && retry < 10) {
              await Future.delayed(const Duration(milliseconds: 500));
              apnsToken = await _fcm.getAPNSToken();
              retry++;
            }
            debugPrint('🍎 [FCM APNs Token]: $apnsToken (after $retry retries)');
          }

          _fcmToken = await _fcm.getToken().timeout(const Duration(seconds: 5));
          debugPrint('🔔 [FCM Token Initialized]: $_fcmToken');
          if (_fcmToken != null) {
            _syncTokenToFirestore(_fcmToken!);
          }

          _fcm.onTokenRefresh.listen((newToken) {
            _fcmToken = newToken;
            _syncTokenToFirestore(newToken);
          });
        } catch (e) {
          debugPrint('🔔 [FCM Init Async] Note: $e');
        }
      }());

      // 5. 포그라운드 메시지 수신 리스너
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('🔔 [FCM Foreground] 수신: ${message.notification?.title} - ${message.notification?.body}');
        
        final notification = message.notification;
        if (notification != null) {
          showLocalNotification(
            title: notification.title ?? '같이타요 알림',
            body: notification.body ?? '',
            payload: message.data['postId'] ?? message.data['type'],
          );
        }
      });

      // 8. 백그라운드에서 알림 클릭하여 앱을 열었을 때
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 [FCM OpenApp] 알림 클릭으로 앱 오픈: ${message.data}');
        onNotificationTap?.call(message.data['postId'] ?? message.data['type']);
      });

      // 9. 앱 종료 상태에서 알림 클릭으로 최초 실행되었을 때
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 [FCM InitialMessage] 앱 실행: ${initialMessage.data}');
        onNotificationTap?.call(initialMessage.data['postId'] ?? initialMessage.data['type']);
      }

      // 10. 전체 공지 및 이벤트 기본 토픽 구독
      try {
        await _fcm.subscribeToTopic('all_users');
        debugPrint('🔔 [FCM Topic] \'all_users\' 토픽 구독 완료');
        await _fcm.subscribeToTopic('events');
        debugPrint('🔔 [FCM Topic] \'events\' 이벤트 토픽 구독 완료');
      } catch (e) {
        debugPrint('🔔 [FCM Topic Init Error]: $e');
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('🔔 [FCM Init Error]: $e');
    }
  }

  /// 🎁 이벤트 및 혜택 알림 토픽 구독/해제 토글
  Future<void> setEventNotificationEnabled(bool enabled) async {
    try {
      if (enabled) {
        await _fcm.subscribeToTopic('events');
        debugPrint('🔔 [FCM Topic] \'events\' 구독 활성화');
      } else {
        await _fcm.unsubscribeFromTopic('events');
        debugPrint('🔔 [FCM Topic] \'events\' 구독 해제');
      }
    } catch (e) {
      debugPrint('🔔 [FCM Topic Toggle Error]: $e');
    }
  }

  /// 📢 특정 토픽 직접 구독
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      debugPrint('🔔 [FCM Topic] \'$topic\' 구독 완료');
    } catch (e) {
      debugPrint('🔔 [FCM Topic Subscribe Error]: $e');
    }
  }

  /// 📢 특정 토픽 구독 해제
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      debugPrint('🔔 [FCM Topic] \'$topic\' 구독 해제 완료');
    } catch (e) {
      debugPrint('🔔 [FCM Topic Unsubscribe Error]: $e');
    }
  }

  /// Firestore에 유저 FCM 토큰 저장
  void _syncTokenToFirestore(String token) {
    try {
      final uid = AppFirebaseService.instance.currentUid;
      if (uid.isNotEmpty && uid != 'guest_user') {
        FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': token,
          'lastTokenUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('🔔 [FCM Token Synced to Firestore for $uid]: $token');
      }
    } catch (e) {
      debugPrint('🔔 토큰 Firestore 저장 실패: $e');
    }
  }

  /// 📲 로그인 완료 시 특정 UID로 FCM 토큰 강제 동기화
  Future<void> syncTokenForUser(String? uid) async {
    final targetUid = (uid != null && uid.isNotEmpty)
        ? uid
        : AppFirebaseService.instance.currentUid;
    if (targetUid.isEmpty || targetUid == 'guest_user') return;

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await _fcm.getAPNSToken();
        int retry = 0;
        while (apnsToken == null && retry < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          apnsToken = await _fcm.getAPNSToken();
          retry++;
        }
        debugPrint('🍎 [APNs Token for sync]: $apnsToken (after $retry retries)');
      }

      _fcmToken = await _fcm.getToken().timeout(const Duration(seconds: 5));
      if (_fcmToken != null && _fcmToken!.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(targetUid).set({
          'fcmToken': _fcmToken,
          'lastTokenUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('🔔 [FCM Token Synced] 유저($targetUid)의 FCM 토큰 동기화 성공: $_fcmToken');
      }
    } catch (e) {
      debugPrint('🔔 [FCM Sync Error]: $e');
    }
  }

  /// 📲 화면 상단에 로컬 알림 배너 즉시 띄우기 & 햅틱 진동 & iOS 홈 화면 배지 숫자 반영
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int? badgeCount,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'eatsleepride_high_channel',
      '같이타요 실시간 알림',
      channelDescription: '동행 참여 신청 및 채팅 메시지 실시간 알림',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: badgeCount,
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: 'default',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    // 📳 실기기 햅틱 진동 발생
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _localNotifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// 🧹 모든 알림 내역 제거 및 앱 아이콘 빨간 배지 숫자 0으로 초기화
  Future<void> clearAllNotificationsAndBadge() async {
    try {
      await _localNotifications.cancelAll();
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: true,
        presentSound: false,
        badgeNumber: 0,
      );
      const notificationDetails = NotificationDetails(
        iOS: darwinDetails,
      );
      await _localNotifications.show(
        999999,
        '',
        '',
        notificationDetails,
      );
      await _localNotifications.cancel(999999);
      debugPrint('🔔 [Badge] 알림 센터 정리 및 앱 배지 0 초기화 완료');
    } catch (e) {
      debugPrint('🔔 [Badge Error]: $e');
    }
  }

  final Set<String> _processedNotificationDocIds = {};
  bool _isInitialSnapshot = true;
  StreamSubscription<QuerySnapshot>? _realtimeNotificationSub;
  Function(String postId, String title, String body)? onChatMessageReceived;
  int Function()? getUnreadBadgeCount;

  /// 📲 실시간 기기 간 알림 리스너 (상대방이 보낸 알림만 내 기기에 수신)
  void startRealtimeNotificationListener({
    String? currentNickname,
    String? currentUid,
    List<String> Function()? getJoinedPostIds,
    int Function()? getBadgeCount,
  }) {
    _realtimeNotificationSub?.cancel();
    if (getBadgeCount != null) {
      getUnreadBadgeCount = getBadgeCount;
    }
    final myNick = currentNickname ?? '';
    final myUid = currentUid ?? '';
    if (myNick.isEmpty && myUid.isEmpty) return;

    debugPrint('🔔 [NotificationListener] 실시간 알림 수신 대기 시작: $myNick ($myUid)');
    _isInitialSnapshot = true;

    _realtimeNotificationSub = FirebaseFirestore.instance
        .collection('notifications')
        .snapshots()
        .listen((snapshot) {
      if (_isInitialSnapshot) {
        for (final doc in snapshot.docs) {
          _processedNotificationDocIds.add(doc.id);
        }
        _isInitialSnapshot = false;
        debugPrint('🔔 [NotificationListener] 기존 과거 알림 ${_processedNotificationDocIds.length}건 캐싱 완료 (과거 알림 팝업 차단)');
        return;
      }

      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final docId = change.doc.id;
          if (_processedNotificationDocIds.contains(docId)) {
            continue;
          }
          _processedNotificationDocIds.add(docId);

          final data = change.doc.data();
          if (data == null) continue;

          final sender = data['sender'] as String? ?? '';
          final senderUid = data['senderUid'] as String? ?? '';

          // 🛡️ 내가 보낸 알림은 내 기기에 절대 띄우지 않음!
          if ((myUid.isNotEmpty && senderUid == myUid) ||
              (myNick.isNotEmpty && sender == myNick)) {
            continue;
          }

          final targetAuthor = data['targetAuthor'] as String? ?? '';
          final targetParticipants = (data['targetParticipants'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [targetAuthor];
          final targetUids = (data['targetUids'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final postId = data['postId'] as String? ?? '';

          // 🎯 수신 대상에 내 UID나 닉네임이 포함되어 있는지 확인
          bool isTarget = false;
          if (myUid.isNotEmpty && targetUids.contains(myUid)) isTarget = true;
          if (myNick.isNotEmpty && targetParticipants.contains(myNick)) isTarget = true;
          if (myNick.isNotEmpty && targetAuthor == myNick) isTarget = true;
          if (postId.isNotEmpty && getJoinedPostIds != null) {
            final joinedIds = getJoinedPostIds();
            if (joinedIds.contains(postId)) isTarget = true;
          }
          if (targetParticipants.isEmpty && targetUids.isEmpty) isTarget = true;
          // 익명 대화방이거나 상대방이 보낸 대화방 알림인 경우 수신 대상으로 인정
          if (!isTarget && postId.isNotEmpty && targetParticipants.any((p) => p.startsWith('익명의라이더'))) {
            isTarget = true;
          }

          if (!isTarget) continue;

          final title = data['title'] as String? ?? '같이타요 알림';
          final body = data['body'] as String? ?? '';

          debugPrint('🔔 [Cross-Device Notification] 수신 알림 트리거: $title - $body');
          
          try {
            HapticFeedback.heavyImpact();
            HapticFeedback.vibrate();
          } catch (_) {}

          final currentBadge = getUnreadBadgeCount?.call();
          showLocalNotification(
            title: title,
            body: body,
            payload: postId,
            badgeCount: currentBadge,
          );

          if (postId.isNotEmpty) {
            onChatMessageReceived?.call(postId, title, body);
          }
        }
      }
    });
  }

  /// 🚀 실시간 알림 전송 (상대방 기기에 푸시 전송, 발신자 기기에는 미노출)
  Future<void> notifyRider({
    required String senderNickname,
    String? senderUid,
    required String targetAuthorName,
    required String title,
    required String body,
    String type = 'ride_join',
    String? postId,
    List<String>? targetParticipants,
    List<String>? targetUids,
  }) async {
    try {
      final participants = targetParticipants ?? [targetAuthorName];
      final uids = targetUids ?? [];
      final safeSenderUid = senderUid ?? AppFirebaseService.instance.currentUid;

      // 1. Firestore notifications 컬렉션에 기록 (수신 대상 기기들이 실시간으로 수신)
      await FirebaseFirestore.instance.collection('notifications').add({
        'sender': senderNickname,
        'senderUid': safeSenderUid,
        'targetAuthor': targetAuthorName,
        'targetParticipants': participants,
        'targetUids': uids,
        'title': title,
        'body': body,
        'type': type,
        'postId': postId ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // ⚠️ 발신자(Sender) 본인 기기에서는 showLocalNotification을 호출하지 않습니다.
    } catch (e) {
      debugPrint('알림 전송 오류: $e');
    }
  }
}
