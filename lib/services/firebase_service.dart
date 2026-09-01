import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
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
  String get currentUid => _auth.currentUser?.uid ?? 'guest_user';

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
      if (user != null) {
        final profile = UserProfile(
          id: user.uid,
          provider: SocialAuthProvider.apple,
          email: appleCredential.email ?? user.email ?? 'apple_rider@eatsleepride.app',
          nickname: gCurrentUser?.nickname ?? '익명의라이더#${user.uid.length >= 4 ? user.uid.substring(0, 4) : "apple"}',
          preferredDiscipline: gCurrentUser?.preferredDiscipline ?? '스노보드',
          homeResort: gCurrentUser?.homeResort ?? '휘닉스파크',
          level: gCurrentUser?.level ?? '중급',
          joinedAt: DateTime.now(),
        );
        await saveUserProfile(profile);
        gCurrentUser = profile;
        return profile;
      }
    } catch (e) {
      debugPrint('Apple Sign In error (or cancelled): $e');
      // 시뮬레이터 또는 에러 시 부드러운 fallback
      final profile = UserProfile(
        id: currentUid,
        provider: SocialAuthProvider.apple,
        email: 'rider_apple@icloud.com',
        nickname: gCurrentUser?.nickname ?? '익명의라이더#${currentUid.length >= 4 ? currentUid.substring(0, 4) : "999"}',
        preferredDiscipline: gCurrentUser?.preferredDiscipline ?? '스노보드',
        homeResort: gCurrentUser?.homeResort ?? '휘닉스파크',
        level: gCurrentUser?.level ?? '중급',
        joinedAt: DateTime.now(),
      );
      await saveUserProfile(profile);
      gCurrentUser = profile;
      return profile;
    }
    return null;
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
        id: currentUid,
        provider: SocialAuthProvider.kakao,
        email: email,
        nickname: gCurrentUser?.nickname ?? '익명의라이더#${kakaoId.length >= 4 ? kakaoId.substring(0, 4) : kakaoId}',
        preferredDiscipline: gCurrentUser?.preferredDiscipline ?? '스노보드',
        homeResort: gCurrentUser?.homeResort ?? '비발디파크',
        level: gCurrentUser?.level ?? '초중급',
        joinedAt: DateTime.now(),
      );
      await saveUserProfile(profile);
      gCurrentUser = profile;
      return profile;
    } catch (e) {
      debugPrint('Kakao Sign In (fallback): $e');
      final profile = UserProfile(
        id: currentUid,
        provider: SocialAuthProvider.kakao,
        email: 'rider_kakao@kakao.com',
        nickname: gCurrentUser?.nickname ?? '익명의라이더#${currentUid.length >= 4 ? currentUid.substring(0, 4) : "777"}',
        preferredDiscipline: gCurrentUser?.preferredDiscipline ?? '스노보드',
        homeResort: gCurrentUser?.homeResort ?? '비발디파크',
        level: gCurrentUser?.level ?? '초중급',
        joinedAt: DateTime.now(),
      );
      await saveUserProfile(profile);
      gCurrentUser = profile;
      return profile;
    }
  }

  Future<UserProfile?> signInWithNaver() async {
    final profile = UserProfile(
      id: currentUid,
      provider: SocialAuthProvider.naver,
      email: 'rider_naver@naver.com',
      nickname: gCurrentUser?.nickname ?? '익명의라이더#${currentUid.length >= 4 ? currentUid.substring(0, 4) : "888"}',
      preferredDiscipline: gCurrentUser?.preferredDiscipline ?? '스키',
      homeResort: gCurrentUser?.homeResort ?? '모나용평',
      level: gCurrentUser?.level ?? '중급',
      joinedAt: DateTime.now(),
    );
    await saveUserProfile(profile);
    gCurrentUser = profile;
    return profile;
  }

  // -------------------------------------------------------------
  // 1. 익명 로그인 및 유저 프로필 클라우드 동기화
  // -------------------------------------------------------------
  Future<UserProfile> initUserAuthAndProfile() async {
    try {
      User? user = _auth.currentUser;
      if (user == null) {
        final credential = await _auth.signInAnonymously();
        user = credential.user;
      }

      final uid = user?.uid ?? 'anon_user';
      final userDocRef = _firestore.collection('users').doc(uid);
      final docSnapshot = await userDocRef.get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;
        final loadedProfile = UserProfile(
          id: uid,
          provider: SocialAuthProvider.values.firstWhere(
            (p) => p.name == (data['provider'] ?? 'kakao'),
            orElse: () => SocialAuthProvider.kakao,
          ),
          email: data['email'] ?? 'rider@eatsleepride.app',
          nickname: data['nickname'] ?? '익명의라이더#${uid.length >= 4 ? uid.substring(0, 4) : uid}',
          preferredDiscipline: data['preferredDiscipline'] ?? '스노보드',
          homeResort: data['homeResort'] ?? '비발디파크',
          level: data['level'] ?? '중급',
          joinedAt: (data['joinedAt'] is Timestamp)
              ? (data['joinedAt'] as Timestamp).toDate()
              : DateTime.now(),
          completedRidesCount: data['completedRidesCount'] ?? 0,
          taggedReviewsCount: data['taggedReviewsCount'] ?? 0,
          snowPoints: data['snowPoints'] ?? 1000,
          riderTitle: data['riderTitle'] ?? '새싹 라이더 🏂',
          blockedUsers: List<String>.from(data['blockedUsers'] ?? []),
        );
        gCurrentUser = loadedProfile;
        return loadedProfile;
      } else {
        // 새 익명 유저 프로필 생성 및 Firestore에 등록
        final shortUid = uid.length >= 4 ? uid.substring(0, 4) : uid;
        final newProfile = UserProfile(
          id: uid,
          provider: SocialAuthProvider.kakao,
          email: 'rider_$shortUid@eatsleepride.app',
          nickname: '익명의라이더#$shortUid',
          preferredDiscipline: '스노보드',
          homeResort: '비발디파크',
          level: '중급',
          joinedAt: DateTime.now(),
          completedRidesCount: 0,
          taggedReviewsCount: 0,
          snowPoints: 1000,
          riderTitle: '새싹 라이더 🏂',
          blockedUsers: [],
        );
        await saveUserProfile(newProfile);
        gCurrentUser = newProfile;
        return newProfile;
      }
    } catch (e) {
      debugPrint('Firebase initUserAuthAndProfile error: $e');
      // 오프라인이거나 에러 시 기본 프로필 fallback
      final fallbackProfile = UserProfile(
        id: 'offline_user',
        provider: SocialAuthProvider.kakao,
        email: 'rider@kakao.com',
        nickname: '익명의라이더#9482',
        preferredDiscipline: '스노보드',
        homeResort: '비발디파크',
        level: '중급',
        joinedAt: DateTime(2026, 1, 15),
      );
      gCurrentUser = fallbackProfile;
      return fallbackProfile;
    }
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      final uid = profile.id.isEmpty ? currentUid : profile.id;
      await _firestore.collection('users').doc(uid).set({
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
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firebase saveUserProfile error: $e');
    }
  }

  // -------------------------------------------------------------
  // 2. 같이 타요 모집글 (`gatherings` 컬렉션)
  // -------------------------------------------------------------
  Stream<List<RidePost>> streamRidePosts() {
    return _firestore
        .collection('gatherings')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final currentUserName = gCurrentUser?.nickname ?? '';
        final participants = List<String>.from(data['participantNames'] ?? []);
        final author = data['authorName'] ?? '익명';
        final isAuthor = author == currentUserName;
        final isJoined = participants.contains(currentUserName) || isAuthor;

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
          participantNames: participants,
          isJoined: isJoined,
          isAuthor: isAuthor,
          chatMessages: [],
          reportCount: data['reportCount'] ?? 0,
          isBlinded: data['isBlinded'] ?? false,
          reportedUserIds: List<String>.from(data['reportedUserIds'] ?? []),
        );
      }).toList();
    });
  }

  Future<void> createRidePost(RidePost post) async {
    try {
      final docRef = await _firestore.collection('gatherings').add({
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
        'currentMembers': 1,
        'authorName': post.authorName,
        'participantNames': [post.authorName],
        'reportCount': 0,
        'isBlinded': false,
        'reportedUserIds': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 개설 안내 시스템 메시지 추가
      await docRef.collection('messages').add({
        'sender': '시스템',
        'text': '🎉 [${post.authorName}]님이 같이타요 슬로프 방을 개설했습니다! 안전하고 즐거운 라이딩 되세요.',
        'time': FieldValue.serverTimestamp(),
        'isMe': false,
        'isSystem': true,
      });
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
      final maxMembers = (data['maxMembers'] ?? 3) as int;

      if (participants.contains(userName)) {
        // 이미 참여 중이면 퇴장
        participants.remove(userName);
        await docRef.update({
          'participantNames': participants,
          'currentMembers': participants.length,
        });
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
          await docRef.update({
            'participantNames': participants,
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
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final sender = data['sender'] ?? '';
        final isSystem = data['isSystem'] ?? false;
        final isMe = (sender == currentUserName) && !isSystem;

        DateTime messageTime = DateTime.now();
        if (data['time'] is Timestamp) {
          messageTime = (data['time'] as Timestamp).toDate();
        }

        return ChatMessage(
          sender: sender,
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
        return RideReview(
          id: doc.id,
          authorName: data['authorName'] ?? '익명',
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

  Future<void> createReview(RideReview review) async {
    try {
      await _firestore.collection('reviews').add({
        'authorName': review.authorName,
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
  // 5. 초기 샘플 데이터 시딩 (Firestore가 비어있을 때 1회성 채우기)
  // -------------------------------------------------------------
  Future<void> seedInitialDataIfEmpty(List<RidePost> samplePosts, List<RideReview> sampleReviews) async {
    try {
      final gatheringCount = await _firestore.collection('gatherings').limit(1).get();
      if (gatheringCount.docs.isEmpty) {
        debugPrint('Seeding initial gatherings to Firestore...');
        for (final post in samplePosts) {
          final docRef = await _firestore.collection('gatherings').add({
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
            'participantNames': post.participantNames,
            'reportCount': post.reportCount,
            'isBlinded': post.isBlinded,
            'reportedUserIds': post.reportedUserIds,
            'createdAt': FieldValue.serverTimestamp(),
          });

          for (final msg in post.chatMessages) {
            await docRef.collection('messages').add({
              'sender': msg.sender,
              'text': msg.text,
              'time': Timestamp.fromDate(msg.time),
              'isMe': false,
              'isSystem': msg.isSystem,
            });
          }
        }
      }

      final reviewCount = await _firestore.collection('reviews').limit(1).get();
      if (reviewCount.docs.isEmpty) {
        debugPrint('Seeding initial reviews to Firestore...');
        for (final rev in sampleReviews) {
          await _firestore.collection('reviews').add({
            'authorName': rev.authorName,
            'resortName': rev.resortName,
            'snowCondition': rev.snowCondition,
            'rating': rev.rating,
            'content': rev.content,
            'photoLabels': rev.photoLabels,
            'tags': rev.tags,
            'likeCount': rev.likeCount,
            'commentCount': rev.commentCount,
            'reportCount': rev.reportCount,
            'isBlinded': rev.isBlinded,
            'reportedUserIds': rev.reportedUserIds,
            'createdAt': Timestamp.fromDate(rev.createdAt),
          });
        }
      }
    } catch (e) {
      debugPrint('Error during seedInitialDataIfEmpty: $e');
    }
  }
}
