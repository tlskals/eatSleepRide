import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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

    try {
      // 1. 백그라운드 핸들러 등록
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 2. 푸시 권한 요청 (iOS / Android 13+)
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('🔔 [FCM] 권한 상태: ${settings.authorizationStatus}');

      // 3. 로컬 알림 플러그인 초기화
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
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

      // 4. Android 고우선순위 알림 채널 생성
      const androidChannel = AndroidNotificationChannel(
        'eatsleepride_high_channel',
        '같이타요 실시간 알림',
        description: '동행 참여 신청 및 채팅 메시지 실시간 알림을 제공합니다.',
        importance: Importance.max,
        playSound: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(androidChannel);
      }

      // 5. iOS 포그라운드 프레젠테이션 옵션 설정
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 6. FCM 토큰 획득 및 유저 문서에 저장
      _fcmToken = await _fcm.getToken();
      debugPrint('🔔 [FCM Token]: $_fcmToken');
      if (_fcmToken != null) {
        _syncTokenToFirestore(_fcmToken!);
      }

      // 토큰 갱신 리스너
      _fcm.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _syncTokenToFirestore(newToken);
      });

      // 7. 포그라운드 메시지 수신 리스너
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

      _isInitialized = true;
    } catch (e) {
      debugPrint('🔔 [FCM Init Error]: $e');
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
      }
    } catch (e) {
      debugPrint('🔔 토큰 Firestore 저장 실패: $e');
    }
  }

  /// 📲 화면 상단에 로컬 알림 배너 즉시 띄우기
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'eatsleepride_high_channel',
      '같이타요 실시간 알림',
      channelDescription: '동행 참여 신청 및 채팅 메시지 실시간 알림',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _localNotifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  StreamSubscription<QuerySnapshot>? _realtimeNotificationSub;

  /// 📲 실시간 기기 간 알림 리스너 (상대방이 보낸 알림만 내 기기에 수신)
  void startRealtimeNotificationListener(String currentNickname) {
    _realtimeNotificationSub?.cancel();
    if (currentNickname.isEmpty) return;

    debugPrint('🔔 [NotificationListener] 실시간 알림 수신 대기 시작: $currentNickname');
    final listenStartTime = DateTime.now().subtract(const Duration(seconds: 5));

    _realtimeNotificationSub = FirebaseFirestore.instance
        .collection('notifications')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final sender = data['sender'] as String? ?? '';
          // 🛡️ 내가 보낸 알림은 내 기기에 절대 띄우지 않음!
          if (sender == currentNickname) continue;

          final targetAuthor = data['targetAuthor'] as String? ?? '';
          final targetParticipants = (data['targetParticipants'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [targetAuthor];

          // 🎯 수신 대상에 내 닉네임이 포함되어 있는지 확인
          if (!targetParticipants.contains(currentNickname) && targetAuthor != currentNickname) {
            continue;
          }

          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null && createdAt.isBefore(listenStartTime)) {
            continue; // 과거 알림은 무시
          }

          final title = data['title'] as String? ?? '같이타요 알림';
          final body = data['body'] as String? ?? '';
          final postId = data['postId'] as String?;

          debugPrint('🔔 [Cross-Device Notification] 수신 알림 트리거: $title - $body');
          showLocalNotification(
            title: title,
            body: body,
            payload: postId,
          );
        }
      }
    });
  }

  /// 🚀 실시간 알림 전송 (상대방 기기에 푸시 전송, 발신자 기기에는 미노출)
  Future<void> notifyRider({
    required String senderNickname,
    required String targetAuthorName,
    required String title,
    required String body,
    String type = 'ride_join',
    String? postId,
    List<String>? targetParticipants,
  }) async {
    try {
      final participants = targetParticipants ?? [targetAuthorName];

      // 1. Firestore notifications 컬렉션에 기록 (수신 대상 기기들이 실시간으로 수신)
      await FirebaseFirestore.instance.collection('notifications').add({
        'sender': senderNickname,
        'targetAuthor': targetAuthorName,
        'targetParticipants': participants,
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
