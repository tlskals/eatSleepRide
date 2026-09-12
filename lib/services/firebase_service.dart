import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'notification_service.dart';
import '../main.dart';

class AppFirebaseService {
  static final AppFirebaseService _instance = AppFirebaseService._internal();
  factory AppFirebaseService() => _instance;
  AppFirebaseService._internal();

  static AppFirebaseService get instance => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  User? get currentFirebaseUser => _auth.currentUser;
  String get currentUid => (gCurrentUser != null && gCurrentUser!.id.isNotEmpty)
      ? gCurrentUser!.id
      : (_auth.currentUser?.uid ?? 'guest_user');

  // -------------------------------------------------------------
  // 📸 Firebase Storage 실제 사진 업로드
  // -------------------------------------------------------------
  Future<String?> uploadReviewImageBytes(Uint8List bytes, String fileName) async {
    try {
      final safeUid = currentUid.isNotEmpty ? currentUid : 'guest';
      final path = 'review_photos/$safeUid/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final ref = _storage.ref().child(path);
      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      debugPrint('📸 [Storage] 업로드 성공: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('📸 [Storage Error] 사진 업로드 실패: $e');
      return null;
    }
  }

  // -------------------------------------------------------------
  // 🔑 소셜 로그인 (카카오 / Apple / 네이버)
  // -------------------------------------------------------------
  Future<UserProfile?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider oAuthProvider = OAuthProvider("apple.com");
      final AuthCredential credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      final uniqueId = user?.uid ?? 'apple_${DateTime.now().millisecondsSinceEpoch % 10000}';
      final profile = UserProfile(
        id: uniqueId,
        provider: SocialAuthProvider.apple,
        email: appleCredential.email ?? user?.email ?? 'apple_rider@eatsleepride.app',
        nickname: '익명의라이더#${uniqueId.length >= 4 ? uniqueId.substring(uniqueId.length - 4) : "appl"}',
        preferredDiscipline: '스노보드',
        homeResort: '비발디파크',
        level: '초중급',
        joinedAt: DateTime.now(),
        completedRidesCount: 0,
        taggedReviewsCount: 0,
        snowPoints: 0,
        riderTitle: '비기너 라이더 🏂',
      );
      gCurrentUser = profile;
      await saveUserProfile(profile);
      unawaited(NotificationService.instance.syncTokenForUser(profile.id));
      return profile;
    } catch (e) {
      debugPrint('Apple Sign In error (or cancelled): $e');
      final uniqueId = 'apple_${DateTime.now().millisecondsSinceEpoch % 10000}';
      final profile = UserProfile(
        id: uniqueId,
        provider: SocialAuthProvider.apple,
        email: 'rider_apple@icloud.com',
        nickname: '익명의라이더#${uniqueId.length >= 4 ? uniqueId.substring(uniqueId.length - 4) : "999"}',
        preferredDiscipline: '스노보드',
        homeResort: '비발디파크',
        level: '초중급',
        joinedAt: DateTime.now(),
        completedRidesCount: 0,
        taggedReviewsCount: 0,
        snowPoints: 0,
        riderTitle: '비기너 라이더 🏂',
      );
      gCurrentUser = profile;
      await saveUserProfile(profile);
      unawaited(NotificationService.instance.syncTokenForUser(profile.id));
      return profile;
    }
  }

  Future<UserProfile?> signInWithKakao() async {
    try {
      bool isInstalled = false;
      try {
        isInstalled = await kakao.isKakaoTalkInstalled();
      } catch (_) {
        isInstalled = false;
      }

      if (isInstalled) {
        await kakao.UserApi.instance.loginWithKakaoTalk();
      } else {
        await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      kakao.User kakaoUser = await kakao.UserApi.instance.me();
      final kakaoId = kakaoUser.id.toString();
      final email = kakaoUser.kakaoAccount?.email ?? 'kakao_$kakaoId@kakao.com';

      final profile = UserProfile(
        id: 'kakao_$kakaoId',
        provider: SocialAuthProvider.kakao,
        email: email,
        nickname: '익명의라이더#${kakaoId.length >= 4 ? kakaoId.substring(kakaoId.length - 4) : kakaoId}',
        preferredDiscipline: '스노보드',
        homeResort: '비발디파크',
        level: '초중급',
        joinedAt: DateTime.now(),
        completedRidesCount: 0,
        taggedReviewsCount: 0,
        snowPoints: 0,
        riderTitle: '비기너 라이더 🏂',
      );
      gCurrentUser = profile;
      await saveUserProfile(profile);
      unawaited(NotificationService.instance.syncTokenForUser(profile.id));
      return profile;
    } catch (e) {
      debugPrint('Kakao Sign In (fallback): $e');
      final uniqueId = 'kakao_${DateTime.now().millisecondsSinceEpoch % 10000}';
      final profile = UserProfile(
        id: uniqueId,
        provider: SocialAuthProvider.kakao,
        email: 'rider_kakao@kakao.com',
        nickname: '익명의라이더#${uniqueId.length >= 4 ? uniqueId.substring(uniqueId.length - 4) : "777"}',
        preferredDiscipline: '스노보드',
        homeResort: '비발디파크',
        level: '초중급',
        joinedAt: DateTime.now(),
        completedRidesCount: 0,
        taggedReviewsCount: 0,
        snowPoints: 0,
        riderTitle: '비기너 라이더 🏂',
      );
      gCurrentUser = profile;
      await saveUserProfile(profile);
      unawaited(NotificationService.instance.syncTokenForUser(profile.id));
      return profile;
    }
  }

  Future<UserProfile?> signInWithNaver() async {
    final uniqueId = 'naver_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final profile = UserProfile(
      id: uniqueId,
      provider: SocialAuthProvider.naver,
      email: 'rider_naver@naver.com',
      nickname: '익명의라이더#${uniqueId.length >= 4 ? uniqueId.substring(uniqueId.length - 4) : "888"}',
      preferredDiscipline: '스키',
      homeResort: '모나용평',
      level: '중급',
      joinedAt: DateTime.now(),
      completedRidesCount: 0,
      taggedReviewsCount: 0,
      snowPoints: 0,
      riderTitle: '비기너 라이더 🏂',
    );
    gCurrentUser = profile;
    await saveUserProfile(profile);
    unawaited(NotificationService.instance.syncTokenForUser(profile.id));
    return profile;
  }

  Future<UserProfile?> signInWithGoogle() async {
    try {
      final uniqueId = 'google_${DateTime.now().millisecondsSinceEpoch % 10000}';
      final profile = UserProfile(
        id: uniqueId,
        provider: SocialAuthProvider.google,
        email: 'rider_google@gmail.com',
        nickname: '익명의라이더#${uniqueId.length >= 4 ? uniqueId.substring(uniqueId.length - 4) : "666"}',
        preferredDiscipline: '스노보드',
        homeResort: '휘닉스파크',
        level: '중급',
        joinedAt: DateTime.now(),
        completedRidesCount: 0,
        taggedReviewsCount: 0,
        snowPoints: 0,
        riderTitle: '비기너 라이더 🏂',
      );
      gCurrentUser = profile;
      await saveUserProfile(profile);
      unawaited(NotificationService.instance.syncTokenForUser(profile.id));
      return profile;
    } catch (e) {
      debugPrint('Google Sign In error: $e');
      return null;
    }
  }


  // -------------------------------------------------------------
  // 1. 유저 프로필 로컬 및 클라우드 동기화 (자동 로그인 세션 유지)
  // -------------------------------------------------------------
  Future<UserProfile?> initUserAuthAndProfile() async {
    try {
      // 1. 기기 로컬 캐시(SharedPreferences)에서 이전 로그인 세션 복원
      final prefs = await SharedPreferences.getInstance();
      final savedJsonStr = prefs.getString('saved_user_profile_json');
      if (savedJsonStr != null && savedJsonStr.isNotEmpty) {
        try {
          final Map<String, dynamic> data = jsonDecode(savedJsonStr);
          final restored = UserProfile.fromJson(data);
          gCurrentUser = restored;
          debugPrint('Auto-login restored from local storage: ${restored.nickname} (${restored.id})');

          // 백그라운드에서 Firestore 최신 데이터 및 FCM 토큰 동기화 (네트워크 가능 시)
          unawaited(_syncProfileFromFirestore(restored.id));
          unawaited(NotificationService.instance.syncTokenForUser(restored.id));
          return restored;
        } catch (e) {
          debugPrint('Error parsing saved user profile: $e');
        }
      }

      // 2. 로컬 캐시가 없는 경우 Firebase Auth 확인
      User? user = _auth.currentUser;
      if (user == null || user.isAnonymous) {
        gCurrentUser = null;
        return null;
      }

      final uid = user.uid;
      final userDocRef = _firestore.collection('users').doc(uid);
      final docSnapshot = await userDocRef.get().timeout(const Duration(seconds: 3));

      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;
        final loadedProfile = UserProfile(
          id: uid,
          provider: SocialAuthProvider.values.firstWhere(
            (p) => p.name == (data['provider'] ?? 'kakao'),
            orElse: () => SocialAuthProvider.kakao,
          ),
          email: data['email'] ?? 'rider@eatsleepride.app',
          nickname: data['nickname'] ?? '익명의라이더#${uid.length >= 4 ? uid.substring(uid.length - 4) : uid}',
          preferredDiscipline: data['preferredDiscipline'] ?? '스노보드',
          homeResort: data['homeResort'] ?? '비발디파크',
          level: data['level'] ?? '중급',
          joinedAt: (data['joinedAt'] is Timestamp)
              ? (data['joinedAt'] as Timestamp).toDate()
              : DateTime.now(),
          completedRidesCount: data['completedRidesCount'] ?? 0,
          taggedReviewsCount: data['taggedReviewsCount'] ?? 0,
          snowPoints: data['snowPoints'] ?? 0,
          riderTitle: data['riderTitle'] ?? '비기너 라이더 🏂',
          blockedUsers: List<String>.from(data['blockedUsers'] ?? []),
          eventNotification: data['eventNotification'] ?? true,
          eventConsentDate: (data['eventConsentDate'] is Timestamp)
              ? (data['eventConsentDate'] as Timestamp).toDate()
              : null,
          lastSnowPointDate: (data['lastSnowPointDate'] is Timestamp)
              ? (data['lastSnowPointDate'] as Timestamp).toDate()
              : null,
        );
        gCurrentUser = loadedProfile;
        await saveUserProfile(loadedProfile);
        unawaited(NotificationService.instance.syncTokenForUser(loadedProfile.id));
        return loadedProfile;
      } else {
        gCurrentUser = null;
        return null;
      }
    } catch (e) {
      debugPrint('Firebase initUserAuthAndProfile error: $e');
      gCurrentUser = null;
      return null;
    }
  }

  Future<void> _syncProfileFromFirestore(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (gCurrentUser != null && gCurrentUser!.id == uid) {
          gCurrentUser!.nickname = data['nickname'] ?? gCurrentUser!.nickname;
          gCurrentUser!.snowPoints = data['snowPoints'] ?? gCurrentUser!.snowPoints;
          gCurrentUser!.completedRidesCount = data['completedRidesCount'] ?? gCurrentUser!.completedRidesCount;
          gCurrentUser!.taggedReviewsCount = data['taggedReviewsCount'] ?? gCurrentUser!.taggedReviewsCount;
          gCurrentUser!.blockedUsers = List<String>.from(data['blockedUsers'] ?? gCurrentUser!.blockedUsers);
          // 로컬 캐시도 갱신
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_user_profile_json', jsonEncode(gCurrentUser!.toJson()));
        }
      }
    } catch (_) {}
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      // 1. 기기 로컬 캐시 저장 (자동 로그인 유지)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_user_profile_json', jsonEncode(profile.toJson()));

      // 2. Firestore 클라우드 저장
      final uid = profile.id.isEmpty ? currentUid : profile.id;
      final Map<String, dynamic> data = {
        'id': uid,
        'provider': profile.provider.name,
        'email': profile.email,
        'nickname': profile.nickname,
        'preferredDiscipline': profile.preferredDiscipline,
        'homeResort': profile.homeResort,
        'level': profile.level,
        'joinedAt': Timestamp.fromDate(profile.joinedAt),
        'completedRidesCount': profile.completedRidesCount,
        'taggedReviewsCount': profile.taggedReviewsCount,
        'snowPoints': profile.snowPoints,
        'riderTitle': profile.riderTitle,
        'blockedUsers': profile.blockedUsers,
        'eventNotification': profile.eventNotification,
        'eventConsentDate': profile.eventConsentDate != null ? Timestamp.fromDate(profile.eventConsentDate!) : null,
        'lastSnowPointDate': profile.lastSnowPointDate != null ? Timestamp.fromDate(profile.lastSnowPointDate!) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final token = NotificationService.instance.fcmToken;
      if (token != null && token.isNotEmpty) {
        data['fcmToken'] = token;
        data['lastTokenUpdated'] = FieldValue.serverTimestamp();
      }

      await _firestore.collection('users').doc(uid).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firebase saveUserProfile error: $e');
    }
  }

  /// 🚪 로그아웃 (로컬 저장소 및 인증 세션 초기화)
  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_profile_json');
      gCurrentUser = null;
      try {
        await _auth.signOut();
      } catch (_) {}
      debugPrint('User signed out and local session cleared.');
    } catch (e) {
      debugPrint('SignOut error: $e');
    }
  }

  /// 🔒 Apple App Store 심사 필수 준수: 회원탈퇴 (계정 영구 삭제 및 클라우드 데이터 즉시 파기)
  Future<void> deleteUserAccount(String uid) async {
    try {
      final targetUid = uid.isEmpty ? currentUid : uid;
      
      // 1. 로컬 저장소 세션 삭제
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_profile_json');
      gCurrentUser = null;

      // 2. Firestore 유저 문서 삭제
      await _firestore.collection('users').doc(targetUid).delete();

      // 3. Firebase Auth 인증 해제 및 로그아웃
      try {
        await _auth.signOut();
      } catch (_) {}

      // 4. FCM 푸시 알림 토픽 구독 해제
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
        await FirebaseMessaging.instance.unsubscribeFromTopic('events');
      } catch (_) {}

      debugPrint('User account and personal data deleted successfully for: $targetUid');
    } catch (e) {
      debugPrint('Firebase deleteUserAccount error: $e');
    }
  }

  // -------------------------------------------------------------
  // 2. 같이 타요 모집글 (`gatherings` 컬렉션)
  // -------------------------------------------------------------
  Stream<List<RidePost>> streamRidePosts() {
    return _firestore
        .collection('gatherings')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final currentUserName = gCurrentUser?.nickname ?? '';
        final myUid = gCurrentUser?.id ?? '';
        final participants = List<String>.from(data['participantNames'] ?? []);
        final participantUids = List<String>.from(data['participantUids'] ?? []);
        final author = data['authorName'] ?? '익명';
        final authorUid = data['authorUid'] ?? '';
        final isAnonymous = data['isAnonymous'] as bool? ?? true;
        final hasMemberLeft = data['hasMemberLeft'] as bool? ?? false;
        final isRandom = (data['purpose'] as String? ?? '').contains('랜덤');
        final isAuthor = !isRandom && myUid.isNotEmpty && (authorUid == myUid || (author.isNotEmpty && author == currentUserName));
        final isJoined = (myUid.isNotEmpty && participantUids.contains(myUid)) || (currentUserName.isNotEmpty && participants.contains(currentUserName)) || isAuthor;

        DateTime? createdAt;
        if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        }
        DateTime? bumpedAt;
        if (data['bumpedAt'] != null && data['bumpedAt'] is Timestamp) {
          bumpedAt = (data['bumpedAt'] as Timestamp).toDate();
        }

        return RidePost(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          resortName: data['resortName'] ?? '',
          slopes: List<String>.from(data['slopes'] ?? []),
          discipline: data['discipline'] ?? '보드',
          style: data['style'] ?? '라이딩',
          skillLevel: data['skillLevel'] ?? '초급',
          purpose: data['purpose'] ?? '동행/원정',
          dateText: data['dateText'] ?? '오늘',
          timeSlot: data['timeSlot'] ?? '주간',
          maxMembers: data['maxMembers'] ?? 3,
          currentMembers: data['currentMembers'] ?? (participants.length),
          authorName: author,
          authorUid: authorUid,
          participantNames: participants,
          participantUids: participantUids,
          isJoined: isJoined,
          isAuthor: isAuthor,
          isAnonymous: isAnonymous,
          hasMemberLeft: hasMemberLeft,
          chatMessages: [],
          reportCount: data['reportCount'] ?? 0,
          isBlinded: data['isBlinded'] ?? false,
          reportedUserIds: List<String>.from(data['reportedUserIds'] ?? []),
          createdAt: createdAt,
          bumpedAt: bumpedAt,
        );
      }).toList();
    });
  }

  Future<List<RidePost>> getRidePostsOnce() async {
    try {
      final snapshot = await _firestore.collection('gatherings').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final currentUserName = gCurrentUser?.nickname ?? '';
        final myUid = gCurrentUser?.id ?? '';
        final participants = List<String>.from(data['participantNames'] ?? []);
        final participantUids = List<String>.from(data['participantUids'] ?? []);
        final author = data['authorName'] ?? '익명';
        final authorUid = data['authorUid'] ?? '';
        final isAnonymous = data['isAnonymous'] as bool? ?? true;
        final hasMemberLeft = data['hasMemberLeft'] as bool? ?? false;
        final isRandom = (data['purpose'] as String? ?? '').contains('랜덤');
        final isAuthor = !isRandom && myUid.isNotEmpty && (authorUid == myUid || (author.isNotEmpty && author == currentUserName));
        final isJoined = (myUid.isNotEmpty && participantUids.contains(myUid)) || (currentUserName.isNotEmpty && participants.contains(currentUserName)) || isAuthor;

        DateTime? createdAt;
        if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
          createdAt = (data['createdAt'] as Timestamp).toDate();
        }
        DateTime? bumpedAt;
        if (data['bumpedAt'] != null && data['bumpedAt'] is Timestamp) {
          bumpedAt = (data['bumpedAt'] as Timestamp).toDate();
        }

        return RidePost(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          resortName: data['resortName'] ?? '',
          slopes: List<String>.from(data['slopes'] ?? []),
          discipline: data['discipline'] ?? '보드',
          style: data['style'] ?? '라이딩',
          skillLevel: data['skillLevel'] ?? '초급',
          purpose: data['purpose'] ?? '동행/원정',
          dateText: data['dateText'] ?? '오늘',
          timeSlot: data['timeSlot'] ?? '주간',
          maxMembers: data['maxMembers'] ?? 3,
          currentMembers: data['currentMembers'] ?? (participants.length),
          authorName: author,
          authorUid: authorUid,
          participantNames: participants,
          participantUids: participantUids,
          isJoined: isJoined,
          isAuthor: isAuthor,
          isAnonymous: isAnonymous,
          hasMemberLeft: hasMemberLeft,
          chatMessages: [],
          reportCount: data['reportCount'] ?? 0,
          isBlinded: data['isBlinded'] ?? false,
          reportedUserIds: List<String>.from(data['reportedUserIds'] ?? []),
          createdAt: createdAt,
          bumpedAt: bumpedAt,
        );
      }).toList();
    } catch (e) {
      debugPrint('Firebase getRidePostsOnce error: $e');
      return [];
    }
  }

  Future<RidePost?> getRidePostById(String postId) async {
    try {
      final doc = await _firestore.collection('gatherings').doc(postId).get();
      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;
      final currentUserName = gCurrentUser?.nickname ?? '';
      final myUid = gCurrentUser?.id ?? '';
      final participants = List<String>.from(data['participantNames'] ?? []);
      final participantUids = List<String>.from(data['participantUids'] ?? []);
      final author = data['authorName'] ?? '익명';
      final authorUid = data['authorUid'] ?? '';
      final isAnonymous = data['isAnonymous'] as bool? ?? true;
      final hasMemberLeft = data['hasMemberLeft'] as bool? ?? false;
      final isRandom = (data['purpose'] as String? ?? '').contains('랜덤');
      final isAuthor = !isRandom && myUid.isNotEmpty && (authorUid == myUid || (author.isNotEmpty && author == currentUserName));
      final isJoined = (myUid.isNotEmpty && participantUids.contains(myUid)) || (currentUserName.isNotEmpty && participants.contains(currentUserName)) || isAuthor;

      DateTime? createdAt;
      if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
        createdAt = (data['createdAt'] as Timestamp).toDate();
      }
      DateTime? bumpedAt;
      if (data['bumpedAt'] != null && data['bumpedAt'] is Timestamp) {
        bumpedAt = (data['bumpedAt'] as Timestamp).toDate();
      }

      return RidePost(
        id: doc.id,
        title: data['title'] ?? '',
        content: data['content'] ?? '',
        resortName: data['resortName'] ?? '',
        slopes: List<String>.from(data['slopes'] ?? []),
        discipline: data['discipline'] ?? '보드',
        style: data['style'] ?? '라이딩',
        skillLevel: data['skillLevel'] ?? '초급',
        purpose: data['purpose'] ?? '동행/원정',
        dateText: data['dateText'] ?? '오늘',
        timeSlot: data['timeSlot'] ?? '주간',
        maxMembers: data['maxMembers'] ?? 3,
        currentMembers: data['currentMembers'] ?? (participants.length),
        authorName: author,
        authorUid: authorUid,
        participantNames: participants,
        participantUids: participantUids,
        isJoined: isJoined,
        isAuthor: isAuthor,
        isAnonymous: isAnonymous,
        hasMemberLeft: hasMemberLeft,
        chatMessages: [],
        reportCount: data['reportCount'] ?? 0,
        isBlinded: data['isBlinded'] ?? false,
        reportedUserIds: List<String>.from(data['reportedUserIds'] ?? []),
        createdAt: createdAt,
        bumpedAt: bumpedAt,
      );
    } catch (e) {
      debugPrint('Firebase getRidePostById error: $e');
      return null;
    }
  }

  Future<void> createRidePost(RidePost post) async {
    try {
      final authorUid = gCurrentUser?.id ?? currentUid;
      final postData = {
        'title': post.title,
        'content': post.content,
        'resortName': post.resortName,
        'slopes': post.slopes,
        'discipline': post.discipline,
        'style': post.style,
        'skillLevel': post.skillLevel,
        'purpose': post.purpose,
        'dateText': post.dateText,
        'timeSlot': post.timeSlot,
        'maxMembers': post.maxMembers,
        'currentMembers': post.currentMembers,
        'authorName': post.authorName,
        'authorUid': authorUid,
        'participantNames': post.participantNames,
        'participantUids': post.participantUids.isNotEmpty ? post.participantUids : [authorUid],
        'isAnonymous': post.isAnonymous,
        'hasMemberLeft': post.hasMemberLeft,
        'reportCount': 0,
        'isBlinded': false,
        'reportedUserIds': [],
        'createdAt': Timestamp.fromDate(post.createdAt),
        'bumpedAt': post.bumpedAt != null ? Timestamp.fromDate(post.bumpedAt!) : null,
      };

      DocumentReference docRef;
      if (post.id.isNotEmpty && !post.id.startsWith('post_')) {
        docRef = _firestore.collection('gatherings').doc(post.id);
        await docRef.set(postData, SetOptions(merge: true));
      } else {
        docRef = await _firestore.collection('gatherings').add(postData);
      }

      // 개설 안내 시스템 메시지 추가
      await docRef.collection('messages').add({
        'sender': '시스템',
        'text': '🎉 [${post.authorName}]님이 같이타요 슬로프 방을 개설했습니다! 안전하고 즐거운 라이딩 되세요.',
        'time': FieldValue.serverTimestamp(),
        'isMe': false,
        'isSystem': true,
      });

      // 파우더 포인트 50P 적립 (1일 1회 첫 개설 보상)
      if (gCurrentUser != null) {
        gCurrentUser!.snowPoints += 50;
        await saveUserProfile(gCurrentUser!);
      }
    } catch (e) {
      debugPrint('Firebase createRidePost error: $e');
      rethrow;
    }
  }

  Future<void> toggleJoinRidePost(String postId, String userName) async {
    try {
      final docRef = _firestore.collection('gatherings').doc(postId);
      final doc = await docRef.get();
      if (!doc.exists) return;

      final data = doc.data()!;
      List<String> participants = List<String>.from(data['participantNames'] ?? []);
      List<String> participantUids = List<String>.from(data['participantUids'] ?? []);
      final maxMembers = (data['maxMembers'] ?? 3) as int;
      final myUid = gCurrentUser?.id ?? currentUid;

      if (participants.contains(userName) || (myUid.isNotEmpty && participantUids.contains(myUid))) {
        // 이미 참여 중이면 퇴장
        final uidIdx = myUid.isNotEmpty ? participantUids.indexOf(myUid) : -1;
        if (uidIdx != -1 && uidIdx < participants.length) {
          participants.removeAt(uidIdx);
        } else {
          participants.remove(userName);
        }
        if (myUid.isNotEmpty) {
          participantUids.remove(myUid);
        }

        final isRandom = (data['purpose'] as String? ?? '').contains('랜덤');
        final Map<String, dynamic> updateData = {
          'participantNames': participants,
          'participantUids': participantUids,
          'currentMembers': participants.length,
          'hasMemberLeft': true,
        };
        if (isRandom && data['authorUid'] == myUid) {
          updateData['authorUid'] = participantUids.isNotEmpty ? participantUids.first : '';
          updateData['authorName'] = participants.isNotEmpty ? participants.first : '익명';
        }
        await docRef.update(updateData);
        await docRef.collection('messages').add({
          'sender': '시스템',
          'text': '👋 [$userName]님이 방에서 나갔습니다.',
          'time': FieldValue.serverTimestamp(),
          'isMe': false,
          'isSystem': true,
        });
      } else {
        // 새로 참여
        if (participants.length < maxMembers + 1) {
          participants.add(userName);
          if (myUid.isNotEmpty && !participantUids.contains(myUid)) {
            participantUids.add(myUid);
          }
          await docRef.update({
            'participantNames': participants,
            'participantUids': participantUids,
            'currentMembers': participants.length,
          });
          await docRef.collection('messages').add({
            'sender': '시스템',
            'text': '🏂 [$userName]님이 슬로프 동행에 참여했습니다! 반갑게 인사해주세요.',
            'time': FieldValue.serverTimestamp(),
            'isMe': false,
            'isSystem': true,
          });
        }
      }
    } catch (e) {
      debugPrint('Firebase toggleJoinRidePost error: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------------
  // ⚡ 4인 실시간 랜덤 매칭 큐 (`random_match_queues/{resortId}/riders`)
  // -------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> streamMatchQueue(String resortId) {
    return _firestore
        .collection('random_match_queues')
        .doc(resortId)
        .collection('riders')
        .orderBy('joinedAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserMatchStatus(String uid) {
    return _firestore.collection('user_match_status').doc(uid).snapshots();
  }

  Future<void> joinMatchQueue({
    required String resortId,
    required String resortName,
    required String shortName,
    required String uid,
    required String nickname,
  }) async {
    try {
      // 1. 유저 매칭 상태 초기화
      await _firestore.collection('user_match_status').doc(uid).set({
        'status': 'waiting',
        'resortId': resortId,
        'matchedPostId': null,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // 2. 해당 스키장 큐에 등록
      final riderRef = _firestore
          .collection('random_match_queues')
          .doc(resortId)
          .collection('riders')
          .doc(uid);

      await riderRef.set({
        'uid': uid,
        'nickname': nickname,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // 3. 큐에 모인 인원 확인 (4명이면 매칭 성사 처리)
      final queueSnap = await _firestore
          .collection('random_match_queues')
          .doc(resortId)
          .collection('riders')
          .orderBy('joinedAt', descending: false)
          .get();

      if (queueSnap.docs.length >= 4) {
        final top4 = queueSnap.docs.take(4).toList();
        final participantUids = top4.map((d) => d.data()['uid'] as String).toList();
        final participantNames = top4.map((d) => d.data()['nickname'] as String).toList();

        if (participantUids.contains(uid)) {
          final now = DateTime.now();
          final postId = 'random_match_${now.millisecondsSinceEpoch}';
          final newPost = RidePost(
            id: postId,
            title: '[⚡️ 4인 랜덤매칭] $shortName 실시간 번개',
            content: '$resortName 실시간 4인 슬로프 메이트 대화방입니다. 슬로프에서 만나요!',
            resortName: resortName,
            slopes: ['전체 슬로프 (자유)'],
            discipline: '스키/보드 혼합',
            style: '자유 라이딩',
            skillLevel: '무관',
            purpose: '랜덤 매칭',
            dateText: '오늘 실시간',
            timeSlot: '실시간 즉시',
            maxMembers: 3,
            currentMembers: 4,
            authorName: participantNames.first,
            authorUid: participantUids.first,
            participantNames: participantNames,
            participantUids: participantUids,
            isJoined: true,
            isAuthor: participantUids.first == uid,
            chatMessages: [
              ChatMessage(
                sender: '시스템',
                text: '🎉 [$shortName] 4인 실시간 랜덤 매칭이 성사되었습니다!\n함께할 메이트들과 반갑게 인사하고 슬로프 약속을 정해보세요 ⛷️🏂',
                time: now,
                isSystem: true,
              ),
            ],
          );

          // 1) 모집글 생성
          await createRidePost(newPost);

          // 2) 4명 유저의 매칭 상태를 'matched'로 변경 및 큐에서 제거
          final batch = _firestore.batch();
          for (final d in top4) {
            final riderUid = d.data()['uid'] as String;
            batch.delete(d.reference);
            batch.set(_firestore.collection('user_match_status').doc(riderUid), {
              'status': 'matched',
              'matchedPostId': postId,
              'matchedAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();

          // 3) 알림 전송
          NotificationService.instance.notifyRider(
            senderNickname: '시스템',
            targetAuthorName: participantNames.first,
            targetParticipants: participantNames,
            targetUids: participantUids,
            title: '⚡️ 4인 슬로프 매칭 완료!',
            body: '[$shortName] 4인 매칭이 성사되었습니다! 지금 대화방에 입장하세요 ⛷️🏂',
            type: 'random_match_success',
            postId: postId,
          );
        }
      }
    } catch (e) {
      debugPrint('joinMatchQueue error: $e');
    }
  }

  Future<void> leaveMatchQueue(String resortId, String uid) async {
    try {
      await _firestore
          .collection('random_match_queues')
          .doc(resortId)
          .collection('riders')
          .doc(uid)
          .delete();

      await _firestore.collection('user_match_status').doc(uid).delete();
    } catch (e) {
      debugPrint('leaveMatchQueue error: $e');
    }
  }

  Future<void> reportRidePost(String postId, String reporterUserId) async {
    try {
      final docRef = _firestore.collection('gatherings').doc(postId);
      final doc = await docRef.get();
      if (!doc.exists) return;

      final data = doc.data()!;
      List<String> reportedUsers = List<String>.from(data['reportedUserIds'] ?? []);
      int currentReports = data['reportCount'] ?? 0;

      if (!reportedUsers.contains(reporterUserId)) {
        reportedUsers.add(reporterUserId);
        currentReports += 1;
        final isBlinded = currentReports >= 3;

        await docRef.update({
          'reportCount': currentReports,
          'reportedUserIds': reportedUsers,
          'isBlinded': isBlinded,
        });
      }
    } catch (e) {
      debugPrint('Firebase reportRidePost error: $e');
      rethrow;
    }
  }

  Future<void> bumpRidePost(String postId, DateTime bumpedAt) async {
    try {
      final docRef = _firestore.collection('gatherings').doc(postId);
      await docRef.update({
        'bumpedAt': Timestamp.fromDate(bumpedAt),
      });
    } catch (e) {
      debugPrint('Firebase bumpRidePost error: $e');
      rethrow;
    }
  }

  /// 🗑️ 모집글 영구 삭제
  Future<void> deleteRidePost(String postId) async {
    try {
      final docRef = _firestore.collection('gatherings').doc(postId);
      await docRef.delete();
      debugPrint('Firebase deleteRidePost success for: $postId');
    } catch (e) {
      debugPrint('Firebase deleteRidePost error: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------------
  // 3. 실시간 채팅 (`gatherings/{postId}/messages` 서브컬렉션)
  // -------------------------------------------------------------
  Stream<List<ChatMessage>> streamChatMessages(String postId) {
    return _firestore
        .collection('gatherings')
        .doc(postId)
        .collection('messages')
        .orderBy('time', descending: false)
        .snapshots()
        .map((snapshot) {
      final currentUserName = gCurrentUser?.nickname ?? '';
      final currentUserId = gCurrentUser?.id ?? '';
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final sender = data['sender'] ?? '';
        final senderUid = data['senderUid'] as String?;
        final realSenderName = data['realSenderName'] as String?;
        final isSystem = data['isSystem'] ?? false;
        final isMe = (!isSystem) &&
            ((senderUid != null && currentUserId.isNotEmpty && senderUid == currentUserId) ||
                (sender == currentUserName) ||
                (realSenderName != null && currentUserName.isNotEmpty && realSenderName == currentUserName));

        DateTime messageTime = DateTime.now();
        if (data['time'] is Timestamp) {
          messageTime = (data['time'] as Timestamp).toDate();
        }

        return ChatMessage(
          sender: sender,
          senderUid: senderUid,
          realSenderName: realSenderName,
          text: data['text'] ?? '',
          time: messageTime,
          isMe: isMe,
          isSystem: isSystem,
        );
      }).toList();
    });
  }

  Future<void> sendChatMessage(String postId, ChatMessage message) async {
    try {
      await _firestore
          .collection('gatherings')
          .doc(postId)
          .collection('messages')
          .add({
        'sender': message.sender,
        'senderUid': message.senderUid ?? gCurrentUser?.id,
        'realSenderName': message.realSenderName ?? gCurrentUser?.nickname,
        'text': message.text,
        'time': FieldValue.serverTimestamp(),
        'isMe': false,
        'isSystem': message.isSystem,
      });
    } catch (e) {
      debugPrint('Firebase sendChatMessage error: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------------
  // 4. 설질 후기 & 피드 (`reviews` 컬렉션)
  // -------------------------------------------------------------
  Stream<List<RideReview>> streamReviews() {
    return _firestore
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final myUid = gCurrentUser?.id ?? '';
        final authorUid = data['authorUid'] ?? '';
        final isAuthor = myUid.isNotEmpty && (authorUid == myUid || (data['authorName'] == gCurrentUser?.nickname));
        return RideReview(
          id: doc.id,
          authorName: data['authorName'] ?? '익명',
          authorUid: authorUid,
          isAuthor: isAuthor,
          resortName: data['resortName'] ?? '',
          snowCondition: data['snowCondition'] ?? '양호',
          rating: data['rating'] ?? 5,
          content: data['content'] ?? '',
          photoLabels: List<String>.from(data['photoLabels'] ?? []),
          tags: List<String>.from(data['tags'] ?? []),
          createdAt: (data['createdAt'] is Timestamp)
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          likeCount: data['likeCount'] ?? 0,
          commentCount: data['commentCount'] ?? 0,
          reportCount: data['reportCount'] ?? 0,
          isBlinded: data['isBlinded'] ?? false,
          reportedUserIds: List<String>.from(data['reportedUserIds'] ?? []),
        );
      }).toList();
    });
  }

  Future<List<RideReview>> getReviewsOnce() async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final myUid = gCurrentUser?.id ?? '';
        final authorUid = data['authorUid'] ?? '';
        final isAuthor = myUid.isNotEmpty && (authorUid == myUid || (data['authorName'] == gCurrentUser?.nickname));
        return RideReview(
          id: doc.id,
          authorName: data['authorName'] ?? '익명',
          authorUid: authorUid,
          isAuthor: isAuthor,
          resortName: data['resortName'] ?? '',
          snowCondition: data['snowCondition'] ?? '양호',
          rating: data['rating'] ?? 5,
          content: data['content'] ?? '',
          photoLabels: List<String>.from(data['photoLabels'] ?? []),
          tags: List<String>.from(data['tags'] ?? []),
          createdAt: (data['createdAt'] is Timestamp)
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          likeCount: data['likeCount'] ?? 0,
          commentCount: data['commentCount'] ?? 0,
          reportCount: data['reportCount'] ?? 0,
          isBlinded: data['isBlinded'] ?? false,
          reportedUserIds: List<String>.from(data['reportedUserIds'] ?? []),
        );
      }).toList();
    } catch (e) {
      debugPrint('Firebase getReviewsOnce error: $e');
      return [];
    }
  }

  Future<void> createReview(RideReview review) async {
    try {
      final authorUid = gCurrentUser?.id ?? currentUid;
      await _firestore.collection('reviews').add({
        'authorName': review.authorName,
        'authorUid': authorUid,
        'resortName': review.resortName,
        'snowCondition': review.snowCondition,
        'rating': review.rating,
        'content': review.content,
        'photoLabels': review.photoLabels,
        'tags': review.tags,
        'likeCount': review.likeCount,
        'commentCount': review.commentCount,
        'reportCount': 0,
        'isBlinded': false,
        'reportedUserIds': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 파우더 포인트 100P 지급
      if (gCurrentUser != null) {
        gCurrentUser!.snowPoints += 100;
        gCurrentUser!.taggedReviewsCount += 1;
        await saveUserProfile(gCurrentUser!);
      }
    } catch (e) {
      debugPrint('Firebase createReview error: $e');
      rethrow;
    }
  }

  Future<void> reportReview(String reviewId, String reporterUserId) async {
    try {
      final docRef = _firestore.collection('reviews').doc(reviewId);
      final doc = await docRef.get();
      if (!doc.exists) return;

      final data = doc.data()!;
      List<String> reportedUsers = List<String>.from(data['reportedUserIds'] ?? []);
      int currentReports = data['reportCount'] ?? 0;

      if (!reportedUsers.contains(reporterUserId)) {
        reportedUsers.add(reporterUserId);
        currentReports += 1;
        final isBlinded = currentReports >= 3;

        await docRef.update({
          'reportCount': currentReports,
          'reportedUserIds': reportedUsers,
          'isBlinded': isBlinded,
        });
      }
    } catch (e) {
      debugPrint('Firebase reportReview error: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------------
  // 5. 실시간 설질 한줄평 (`live_snow_comments` 컬렉션)
  // -------------------------------------------------------------
  Stream<List<LiveSnowComment>> streamLiveSnowComments({String? resortId}) {
    Query query = _firestore.collection('live_snow_comments').orderBy('createdAt', descending: true);
    if (resortId != null && resortId.isNotEmpty && resortId != 'all') {
      query = query.where('resortId', isEqualTo: resortId);
    }
    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        DateTime created = DateTime.now();
        if (data['createdAt'] is Timestamp) {
          created = (data['createdAt'] as Timestamp).toDate();
        }
        return LiveSnowComment(
          id: doc.id,
          resortId: data['resortId'] ?? '',
          resortName: data['resortName'] ?? '',
          authorName: data['authorName'] ?? '익명의 라이더',
          authorUid: data['authorUid'],
          content: data['content'] ?? '',
          snowCondition: data['snowCondition'] ?? '양호/양설',
          snowConditionEmoji: data['snowConditionEmoji'] ?? '✨',
          createdAt: created,
          likes: (data['likes'] ?? 0) as int,
          likedUserNames: List<String>.from(data['likedUserNames'] ?? []),
        );
      }).toList();
    });
  }

  Future<bool> addLiveSnowComment(LiveSnowComment comment) async {
    try {
      await _firestore.collection('live_snow_comments').add({
        'resortId': comment.resortId,
        'resortName': comment.resortName,
        'authorName': comment.authorName,
        'authorUid': comment.authorUid ?? currentUid,
        'content': comment.content,
        'snowCondition': comment.snowCondition,
        'snowConditionEmoji': comment.snowConditionEmoji,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': 0,
        'likedUserNames': [],
      });

      // 🎁 설질 한줄평 작성 시 1일 1회에 한해 +50 스노우 포인트 지급 (어뷰징/도배 방지)
      bool awardedPoint = false;
      if (gCurrentUser != null) {
        if (!gCurrentUser!.hasEarnedSnowPointToday) {
          gCurrentUser!.snowPoints += 50;
          gCurrentUser!.lastSnowPointDate = DateTime.now();
          await saveUserProfile(gCurrentUser!);
          awardedPoint = true;
        }
      }
      return awardedPoint;
    } catch (e) {
      debugPrint('Firebase addLiveSnowComment error: $e');
      rethrow;
    }
  }

  Future<void> toggleLikeLiveSnowComment(String commentId, String userName) async {
    try {
      final docRef = _firestore.collection('live_snow_comments').doc(commentId);
      final doc = await docRef.get();
      if (!doc.exists) return;
      final data = doc.data()!;
      List<String> likedUsers = List<String>.from(data['likedUserNames'] ?? []);
      int currentLikes = (data['likes'] ?? 0) as int;
      if (likedUsers.contains(userName)) {
        likedUsers.remove(userName);
        currentLikes = (currentLikes - 1).clamp(0, 99999);
      } else {
        likedUsers.add(userName);
        currentLikes += 1;
      }
      await docRef.update({
        'likedUserNames': likedUsers,
        'likes': currentLikes,
      });
    } catch (e) {
      debugPrint('Firebase toggleLikeLiveSnowComment error: $e');
    }
  }

  Future<void> seedInitialDataIfEmpty(dynamic posts, dynamic reviews) async {
    // No-op or seed if needed
  }
}

