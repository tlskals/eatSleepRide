import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // 🟡 카카오 SDK 초기화
  KakaoSdk.init(
    nativeAppKey: 'c6a747117409de895acefc4b77fa969c',
  );

  // 🛡️ Apple Guideline 1.2 & 매칭 페널티 로컬 캐시 즉시 복원 (앱 재실행 악용 원천 차단)
  unawaited(loadHiddenContentIds());
  await loadMatchPenaltyState();

  // 🚀 앱 UI를 먼저 즉시 띄워 아이폰 실기기 스플래시 화면 멈춤 현상 원천 차단
  runApp(const MyApp());

  // 백그라운드에서 유저 세션 복원 및 푸시 알림 비동기 초기화 (블로킹 방지)
  unawaited(AppFirebaseService.instance.initUserAuthAndProfile());
  unawaited(NotificationService.instance.initialize());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '같이타요',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// -------------------------------------------------------------
// 데이터 모델
// -------------------------------------------------------------

final ValueNotifier<int> gUnreadChatCountNotifier = ValueNotifier<int>(0);

class SkiWebcam {
  final String name;
  final String location;
  final String streamUrl;

  const SkiWebcam({
    required this.name,
    required this.location,
    required this.streamUrl,
  });
}

class DailyWeatherForecast {
  final String date;
  final String dayName;
  final double maxTemp;
  final double minTemp;
  final double snowfall;
  final String weatherDesc;
  final String iconEmoji;

  const DailyWeatherForecast({
    required this.date,
    required this.dayName,
    required this.maxTemp,
    required this.minTemp,
    this.snowfall = 0.0,
    required this.weatherDesc,
    required this.iconEmoji,
  });
}

class ResortWeather {
  final double temp;
  final double apparentTemp;
  final double windSpeed;
  final int humidity;
  final String weatherDesc;
  final String iconEmoji;
  final List<DailyWeatherForecast> dailyForecasts;

  const ResortWeather({
    required this.temp,
    required this.apparentTemp,
    required this.windSpeed,
    required this.humidity,
    required this.weatherDesc,
    required this.iconEmoji,
    this.dailyForecasts = const [],
  });

  factory ResortWeather.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>? ?? {};
    final double temp = (current['temperature_2m'] as num?)?.toDouble() ?? -2.5;
    final double apparentTemp = (current['apparent_temperature'] as num?)?.toDouble() ?? -5.0;
    final double windSpeed = (current['wind_speed_10m'] as num?)?.toDouble() ?? 2.0;
    final int humidity = (current['relative_humidity_2m'] as num?)?.toInt() ?? 55;
    final int code = (current['weather_code'] as num?)?.toInt() ?? 0;

    String desc = _parseWeatherDesc(code);
    String emoji = _parseWeatherEmoji(code);

    List<DailyWeatherForecast> forecasts = [];
    if (json.containsKey('daily')) {
      final daily = json['daily'] as Map<String, dynamic>;
      final times = (daily['time'] as List<dynamic>?) ?? [];
      final codes = (daily['weather_code'] as List<dynamic>?) ?? [];
      final maxTemps = (daily['temperature_2m_max'] as List<dynamic>?) ?? [];
      final minTemps = (daily['temperature_2m_min'] as List<dynamic>?) ?? [];
      final snowfalls = (daily['snowfall_sum'] as List<dynamic>?) ?? [];

      final now = DateTime.now();
      final weekDays = ['월', '화', '수', '목', '금', '토', '일'];

      for (int i = 0; i < times.length && i < 5; i++) {
        final dateStr = times[i].toString();
        final parts = dateStr.split('-');
        final monthDay = parts.length >= 3 ? '${parts[1]}/${parts[2]}' : dateStr;
        
        final dt = now.add(Duration(days: i));
        String dayLabel = i == 0 ? '오늘' : (i == 1 ? '내일' : weekDays[(dt.weekday - 1) % 7]);

        final c = i < codes.length ? (codes[i] as num).toInt() : 0;
        final maxT = i < maxTemps.length ? (maxTemps[i] as num).toDouble() : (temp + 2.0);
        final minT = i < minTemps.length ? (minTemps[i] as num).toDouble() : (temp - 4.0);
        final snow = i < snowfalls.length ? (snowfalls[i] as num).toDouble() : 0.0;

        forecasts.add(
          DailyWeatherForecast(
            date: monthDay,
            dayName: '$dayLabel (${weekDays[(dt.weekday - 1) % 7]})',
            maxTemp: maxT,
            minTemp: minT,
            snowfall: snow,
            weatherDesc: _parseWeatherDesc(c),
            iconEmoji: snow > 0 ? '❄️' : _parseWeatherEmoji(c),
          ),
        );
      }
    }

    return ResortWeather(
      temp: temp,
      apparentTemp: apparentTemp,
      windSpeed: windSpeed,
      humidity: humidity,
      weatherDesc: desc,
      iconEmoji: emoji,
      dailyForecasts: forecasts,
    );
  }

  static String _parseWeatherDesc(int code) {
    if (code == 0) return '맑음';
    if (code >= 1 && code <= 3) return '구름많음';
    if (code == 45 || code == 48) return '안개';
    if (code >= 71 && code <= 77 || code == 85 || code == 86) return '눈 ❄️';
    if (code >= 51 && code <= 67 || code >= 80 && code <= 82) return '비';
    if (code >= 95) return '뇌우';
    return '맑음';
  }

  static String _parseWeatherEmoji(int code) {
    if (code == 0) return '☀️';
    if (code >= 1 && code <= 3) return '⛅';
    if (code == 45 || code == 48) return '🌫️';
    if (code >= 71 && code <= 77 || code == 85 || code == 86) return '❄️';
    if (code >= 51 && code <= 67 || code >= 80 && code <= 82) return '🌧️';
    if (code >= 95) return '⚡';
    return '☀️';
  }
}

enum SlopeStatus {
  open('운영중', Color(0xFF16A34A), Icons.check_circle_rounded),
  closed('미운영/마감', Color(0xFFEF4444), Icons.cancel_rounded),
  mogul('모굴 전용', Color(0xFFEA580C), Icons.waves_rounded),
  park('파크/키커', Color(0xFF7C3AED), Icons.sports_kabaddi_rounded),
  maintenance('정설/대기', Color(0xFFF59E0B), Icons.build_circle_rounded);

  final String label;
  final Color color;
  final IconData icon;
  const SlopeStatus(this.label, this.color, this.icon);
}

enum SlopeDifficulty {
  beginner('초급', Color(0xFF22C55E)),
  novice('초중급', Color(0xFF06B6D4)),
  intermediate('중급', Color(0xFF3B82F6)),
  advanced('중상급', Color(0xFF8B5CF6)),
  expert('상급', Color(0xFFEF4444)),
  extreme('최상급', Color(0xFF0F172A)),
  park('익스트림파크', Color(0xFFD97706));

  final String label;
  final Color color;
  const SlopeDifficulty(this.label, this.color);
}

class DetailedSlope {
  final String name;
  final String section;
  final SlopeDifficulty difficulty;
  final SlopeStatus status;
  final String length;
  final String note;
  final double mapX;
  final double mapY;

  const DetailedSlope({
    required this.name,
    this.section = '메인 구역',
    required this.difficulty,
    this.status = SlopeStatus.open,
    this.length = '',
    this.note = '',
    this.mapX = 0.5,
    this.mapY = 0.5,
  });

  String get displayName => '$name (${difficulty.label})';
}

class SkiResort {
  final String id;
  final String name;
  final String shortName;
  final String region;
  final double lat;
  final double lng;
  final List<DetailedSlope> detailedSlopes;
  final List<String> availableTimeSlots;
  final String officialWebcamUrl;
  final IconData icon;
  final Color themeColor;

  const SkiResort({
    required this.id,
    required this.name,
    required this.shortName,
    required this.region,
    required this.lat,
    required this.lng,
    required this.detailedSlopes,
    this.availableTimeSlots = const ['주간 (09~17)', '오후 (13~17)', '야간 (18~22)'],
    required this.officialWebcamUrl,
    this.icon = Icons.snowboarding_rounded,
    this.themeColor = const Color(0xFF2563EB),
  });

  List<SkiWebcam> get webcams => const [];
  List<String> get slopes => detailedSlopes.map((s) => s.displayName).toList();
  String get logoAsset => 'assets/logos/$id.png';
  String get trailMapAsset => 'assets/trailmaps/$id.png';
}

class ChatMessage {
  final String sender;
  final String? senderUid;
  final String? realSenderName;
  final String text;
  final DateTime time;
  final bool isMe;
  final bool isSystem;

  ChatMessage({
    required this.sender,
    this.senderUid,
    this.realSenderName,
    required this.text,
    required this.time,
    this.isMe = false,
    this.isSystem = false,
  });
}

class RidePost {
  final String id;
  final String? authorUid;
  final String title;
  final String content;
  final String resortName;
  final List<String> slopes;
  final String discipline;
  final String style;
  final String skillLevel;
  final String purpose;
  final String dateText;
  final String timeSlot;
  final int maxMembers;
  int currentMembers;
  final String authorName;
  List<String> participantNames;
  List<String> participantUids;
  bool hasMemberLeft;
  bool isJoined;
  bool isAuthor;
  bool needsRefill;
  final List<ChatMessage> chatMessages;
  int unreadCount; // 💬 읽지 않은 신규 메시지 수
  DateTime createdAt;
  DateTime? bumpedAt;

  // 🚨 실시간 신고 및 3회 누적 자동 블라인드
  int reportCount;
  bool isBlinded;
  List<String> reportedUserIds;

  // 🛡️ 익명 모드 (기본값 ON: '익명의라이더 A, B, C, D' 순차 부여)
  bool isAnonymous;

  RidePost({
    required this.id,
    this.authorUid,
    required this.title,
    required this.content,
    required this.resortName,
    required this.slopes,
    required this.discipline,
    required this.style,
    required this.skillLevel,
    required this.purpose,
    required this.dateText,
    required this.timeSlot,
    required this.maxMembers,
    this.currentMembers = 1,
    required this.authorName,
    List<String>? participantNames,
    List<String>? participantUids,
    this.hasMemberLeft = false,
    this.isJoined = false,
    this.isAuthor = false,
    this.needsRefill = false,
    required this.chatMessages,
    this.unreadCount = 0,
    DateTime? createdAt,
    this.bumpedAt,
    this.reportCount = 0,
    this.isBlinded = false,
    List<String>? reportedUserIds,
    this.isAnonymous = true,
  })  : createdAt = createdAt ?? DateTime.now(),
        participantNames = participantNames ?? [authorName],
        participantUids = participantUids ?? (authorUid != null ? [authorUid] : []),
        reportedUserIds = reportedUserIds ?? [];

  static const List<String> kAnonymousLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

  String getNextAnonymousName() {
    final nextIndex = participantNames.length;
    final letter = kAnonymousLetters[nextIndex % kAnonymousLetters.length];
    return '익명의라이더 $letter';
  }

  DateTime get expiresAt {
    final base = createdAt;
    if (base.hour < 2) {
      // 00:00 ~ 01:59에 작성된 경우 -> 당일 02:00 만료
      return DateTime(base.year, base.month, base.day, 2, 0, 0);
    } else {
      // 02:00 이후 작성된 경우 -> 익일 02:00 만료
      final nextDay = base.add(const Duration(days: 1));
      return DateTime(nextDay.year, nextDay.month, nextDay.day, 2, 0, 0);
    }
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isFull => currentMembers >= (maxMembers + 1);
  bool get canAccessChat =>
      gCurrentUser != null &&
      (isAuthor || isJoined || (gCurrentUser?.nickname != null && participantNames.contains(gCurrentUser!.nickname))) &&
      !isExpired &&
      !isBlinded;

  // 🛡️ Apple Guideline 1.2: 로컬 피드 즉시 숨김(Immediate Removal) 및 신고 즉시 숨김
  bool get shouldHide =>
      isBlinded ||
      reportCount >= 3 ||
      isExpired ||
      (gCurrentUser != null && reportedUserIds.contains(gCurrentUser!.id)) ||
      gHiddenContentIds.contains(id);
}

// 🛡️ Apple Guideline 1.2: 피드에서 즉시 숨김(Immediate Removal) 처리된 항목 ID 세트 및 영구 로컬 캐시
final Set<String> gHiddenContentIds = <String>{};

Future<void> loadHiddenContentIds() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('hidden_content_ids') ?? [];
    gHiddenContentIds.addAll(list);
  } catch (e) {
    debugPrint('Error loading hidden content ids: $e');
  }
}

Future<void> hideContentPermanently(String id) async {
  gHiddenContentIds.add(id);
  try {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('hidden_content_ids') ?? [];
    if (!list.contains(id)) {
      list.add(id);
      await prefs.setStringList('hidden_content_ids', list);
    }
  } catch (e) {
    debugPrint('Error saving hidden content id: $e');
  }
}


// -------------------------------------------------------------
// OAuth 소셜 인증 및 사용자 프로필 모델 (카카오, Apple, Google 전용)
// -------------------------------------------------------------

enum SocialAuthProvider {
  kakao,
  apple,
  google,
}

// -------------------------------------------------------------
// 슬로프 배지 모델
// -------------------------------------------------------------

class RiderBadge {
  final String id;
  final String title;
  final String emoji;
  final String description;
  final bool isUnlocked;
  final String unlockedDate;

  const RiderBadge({
    required this.id,
    required this.title,
    required this.emoji,
    required this.description,
    required this.isUnlocked,
    this.unlockedDate = '',
  });
}

class UserProfile {
  final String id;
  final SocialAuthProvider provider;
  final String email;
  String nickname;
  String preferredDiscipline;
  String homeResort;
  String level;
  final DateTime joinedAt;

  // 🏂 나의 슬로프 활동 지표 & 계정 가꾸기 데이터
  int completedRidesCount; // 같이타요 성사 횟수
  int taggedReviewsCount; // 태그/작성된 후기 개수
  int snowPoints; // 슬로프 파우더 포인트
  String riderTitle; // 라이더 등급/칭호
  List<String> blockedUsers; // 차단한 사용자 닉네임 목록
  bool eventNotification; // 🎁 시즌 이벤트 및 혜택 알림 수신 동의 여부 (정보통신망법)
  DateTime? eventConsentDate; // 수신 동의/변경 일시
  DateTime? lastSnowPointDate;
  DateTime? lastAttendanceDate; // 📅 매일 첫 접속 출석체크 일시

  bool get hasEarnedSnowPointToday {
    if (lastSnowPointDate == null) return false;
    final cutoff = AppFirebaseService.getDailySnowPointCutoffTime();
    return lastSnowPointDate!.isAfter(cutoff);
  }

  bool get hasCheckedInToday {
    if (lastAttendanceDate == null) return false;
    final now = DateTime.now();
    return lastAttendanceDate!.year == now.year &&
           lastAttendanceDate!.month == now.month &&
           lastAttendanceDate!.day == now.day;
  }

  /// 🎖️ 동행 성사 횟수(completedRidesCount) 및 설질 포인트(snowPoints) 기준 실시간 자동 언락 뱃지
  List<RiderBadge> get badges => [
    RiderBadge(
      id: 'first_ride',
      title: '첫 동행 성사',
      emoji: '⛷️',
      description: '첫 같이타요 슬로프 동행 1회 완료 시 획득',
      isUnlocked: completedRidesCount >= 1,
      unlockedDate: completedRidesCount >= 1 ? '조건 달성' : '미획득',
    ),
    RiderBadge(
      id: 'ride_veteran',
      title: '동행 베테랑',
      emoji: '🏂',
      description: '슬로프 동행 3회 이상 완료 시 획득',
      isUnlocked: completedRidesCount >= 3,
      unlockedDate: completedRidesCount >= 3 ? '조건 달성' : '미획득',
    ),
    RiderBadge(
      id: 'ride_master',
      title: '슬로프 마스터',
      emoji: '🏆',
      description: '슬로프 동행 5회 이상 완료 시 획득',
      isUnlocked: completedRidesCount >= 5,
      unlockedDate: completedRidesCount >= 5 ? '조건 달성' : '미획득',
    ),
    RiderBadge(
      id: 'powder_sprout',
      title: '설질 새싹',
      emoji: '❄️',
      description: '설질 포인트 50P 이상 달성 시 획득',
      isUnlocked: snowPoints >= 50,
      unlockedDate: snowPoints >= 50 ? '조건 달성' : '미획득',
    ),
    RiderBadge(
      id: 'powder_collector',
      title: '파우더 수집가',
      emoji: '✨',
      description: '설질 포인트 150P 이상 달성 시 획득',
      isUnlocked: snowPoints >= 150,
      unlockedDate: snowPoints >= 150 ? '조건 달성' : '미획득',
    ),
    RiderBadge(
      id: 'powder_ambassador',
      title: '설질 앰버서더',
      emoji: '👑',
      description: '설질 포인트 300P 이상 달성 시 획득',
      isUnlocked: snowPoints >= 300,
      unlockedDate: snowPoints >= 300 ? '조건 달성' : '미획득',
    ),
  ];

  String get effectiveRiderTitle {
    if (completedRidesCount >= 5 || snowPoints >= 300) {
      return '골드 마스터 🏆';
    } else if (completedRidesCount >= 3 || snowPoints >= 150) {
      return '실버 라이더 🏂';
    } else if (completedRidesCount >= 1 || snowPoints >= 50) {
      return '슬로프 라이더 ⛷️';
    }
    return riderTitle.isNotEmpty ? riderTitle : '비기너 라이더 🏂';
  }

  UserProfile({
    required this.id,
    required this.provider,
    required this.email,
    required this.nickname,
    this.preferredDiscipline = '스노보드',
    this.homeResort = '비발디파크',
    this.level = '중급',
    required this.joinedAt,
    this.completedRidesCount = 0,
    this.taggedReviewsCount = 0,
    this.snowPoints = 0,
    String? riderTitle,
    List<RiderBadge>? badges,
    List<String>? blockedUsers,
    this.eventNotification = true,
    this.eventConsentDate,
    this.lastSnowPointDate,
    this.lastAttendanceDate,
  })  : riderTitle = riderTitle ?? '비기너 라이더 🏂',
        blockedUsers = blockedUsers ?? [];

  String get disciplineAvatarAsset {
    if (preferredDiscipline.contains('보드')) {
      return 'assets/logos/penguin_board.png';
    }
    return 'assets/logos/penguin_ski.png';
  }

  String get providerDisplayName {
    switch (provider) {
      case SocialAuthProvider.kakao:
        return '카카오 계정 연동';
      case SocialAuthProvider.apple:
        return 'Apple ID 연동';
      case SocialAuthProvider.google:
        return 'Google 계정 연동';
    }
  }

  Color get providerColor {
    switch (provider) {
      case SocialAuthProvider.kakao:
        return const Color(0xFFFEE500);
      case SocialAuthProvider.apple:
        return Colors.black;
      case SocialAuthProvider.google:
        return Colors.white;
    }
  }

  Color get providerTextColor {
    switch (provider) {
      case SocialAuthProvider.kakao:
        return const Color(0xFF191919);
      case SocialAuthProvider.apple:
        return Colors.white;
      case SocialAuthProvider.google:
        return const Color(0xFF1F1F1F);
    }
  }

  bool isUserBlocked(String nicknameOrUid, {String? uid}) {
    // 1. 내 자신은 절대 차단 대상이 아님
    if (uid != null && uid.isNotEmpty && uid == id) return false;
    if (id.isNotEmpty && (nicknameOrUid == id || (uid != null && uid == id))) return false;

    // 2. uid가 제공된 경우 uid로 우선 검사
    if (uid != null && uid.isNotEmpty) {
      if (blockedUsers.any((b) => b.trim().toLowerCase() == uid.trim().toLowerCase())) {
        return true;
      }
    }

    final trimmed = nicknameOrUid.trim();
    if (trimmed.isEmpty) return false;

    // 3. 익명 닉네임 문자열("익명의라이더 A" 등)로는 절대 차단 여부를 판단하지 않음!
    final cleanInput = trimmed.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
    if (cleanInput.isEmpty ||
        cleanInput.startsWith('익명의') ||
        cleanInput.startsWith('익명') ||
        cleanInput == '시스템' ||
        cleanInput == '나' ||
        cleanInput == '나 (방장)' ||
        cleanInput == nickname.trim().toLowerCase()) {
      return false;
    }

    return blockedUsers.any((blocked) {
      final cleanBlocked = blocked.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
      if (cleanBlocked.isEmpty || cleanBlocked.startsWith('익명의') || cleanBlocked.startsWith('익명')) {
        return false;
      }
      return cleanBlocked == cleanInput || blocked.toLowerCase() == trimmed.toLowerCase();
    });
  }

  void blockUser(String uidOrNickname) {
    final trimmed = uidOrNickname.trim();
    final clean = trimmed.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
    // 익명 별칭, 자기 자신, 시스템은 차단 목록에 등록 불가
    if (clean.isEmpty ||
        trimmed == id ||
        clean.startsWith('익명의') ||
        clean.startsWith('익명') ||
        clean == '시스템' ||
        clean == '나' ||
        clean == '나 (방장)' ||
        clean == nickname.trim().toLowerCase()) {
      return;
    }
    if (!blockedUsers.contains(trimmed)) {
      blockedUsers.add(trimmed);
    }
  }

  void unblockUser(String uidOrNickname) {
    final trimmed = uidOrNickname.trim().toLowerCase();
    final clean = trimmed.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
    blockedUsers.removeWhere((b) {
      final cleanB = b.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
      return b.toLowerCase() == trimmed || cleanB == clean;
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider': provider.name,
      'email': email,
      'nickname': nickname,
      'preferredDiscipline': preferredDiscipline,
      'homeResort': homeResort,
      'level': level,
      'joinedAt': joinedAt.toIso8601String(),
      'completedRidesCount': completedRidesCount,
      'taggedReviewsCount': taggedReviewsCount,
      'snowPoints': snowPoints,
      'riderTitle': riderTitle,
      'blockedUsers': blockedUsers,
      'eventNotification': eventNotification,
      'eventConsentDate': eventConsentDate?.toIso8601String(),
      'lastSnowPointDate': lastSnowPointDate?.toIso8601String(),
      'lastAttendanceDate': lastAttendanceDate?.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      provider: SocialAuthProvider.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => SocialAuthProvider.kakao,
      ),
      email: json['email'] ?? '',
      nickname: json['nickname'] ?? '',
      preferredDiscipline: json['preferredDiscipline'] ?? '스노보드',
      homeResort: json['homeResort'] ?? '비발디파크',
      level: json['level'] ?? '중급',
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt']) ?? DateTime.now()
          : DateTime.now(),
      completedRidesCount: json['completedRidesCount'] ?? 0,
      taggedReviewsCount: json['taggedReviewsCount'] ?? 0,
      snowPoints: json['snowPoints'] ?? 0,
      riderTitle: json['riderTitle'] ?? '비기너 라이더 🏂',
      blockedUsers: (List<String>.from(json['blockedUsers'] ?? []))
          .where((b) {
            final lower = b.trim().toLowerCase();
            return lower.isNotEmpty &&
                !lower.startsWith('익명의') &&
                !lower.startsWith('익명') &&
                lower != '시스템' &&
                lower != '나' &&
                lower != '나 (방장)';
          })
          .toList(),
      eventNotification: json['eventNotification'] ?? true,
      eventConsentDate: json['eventConsentDate'] != null
          ? DateTime.tryParse(json['eventConsentDate'])
          : null,
      lastSnowPointDate: json['lastSnowPointDate'] != null
          ? DateTime.tryParse(json['lastSnowPointDate'])
          : null,
      lastAttendanceDate: json['lastAttendanceDate'] != null
          ? DateTime.tryParse(json['lastAttendanceDate'])
          : null,
    );
  }
}

// -------------------------------------------------------------
// 기본 로그인 사용자 (반응형 전역 상태 노티파이어)
// -------------------------------------------------------------
class CurrentUserNotifier extends ValueNotifier<UserProfile?> {
  CurrentUserNotifier(super.value);

  void notifyChanged() {
    notifyListeners();
  }
}

final CurrentUserNotifier gCurrentUserNotifier = CurrentUserNotifier(null);

UserProfile? get gCurrentUser => gCurrentUserNotifier.value;
set gCurrentUser(UserProfile? val) {
  gCurrentUserNotifier.value = val;
  gCurrentUserNotifier.notifyChanged();
}

void notifyCurrentUserChanged() {
  gCurrentUserNotifier.notifyChanged();
}

// 1일 랜덤 매칭 횟수 제한 (클린한 만남 & 어뷰징 방지)
int gDailyRandomMatchLimit = 1;
int gDailyRandomMatchRemaining = 1;
DateTime? gPostBanUntil; // 🚨 랜덤 매칭 중도 퇴장 탈주 시 2시간 작성/참여 페널티 만료 시간
DateTime? gPartySkipCooldownUntil; // ⏱️ 파티 수락 창에서 '다음에 하기' 거절(또는 강제종료 이탈) 시 5분간 매칭 제한 만료 시간
bool gBypassWritingHoursForQA = false; // 🛠️ QA 샌드박스용 시간제한 우회

Duration getRemainingSkipCooldown() {
  if (gPartySkipCooldownUntil == null) return Duration.zero;
  final diff = gPartySkipCooldownUntil!.difference(DateTime.now());
  return diff.isNegative ? Duration.zero : diff;
}

Future<void> loadMatchPenaltyState() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    int maxUntilMs = prefs.getInt('party_skip_cooldown_until_ms') ?? 0;

    final uid = gCurrentUser?.id;
    if (uid != null && uid.isNotEmpty) {
      final userUntilMs = prefs.getInt('party_skip_cooldown_until_$uid') ?? 0;
      if (userUntilMs > maxUntilMs) maxUntilMs = userUntilMs;
    }

    // 🛡️ 악용 방지: 매칭 수락 모달이 뜬 상태에서 버튼 대신 앱을 강제 종료한 경우에도 동일하게 5분 페널티 유지 및 방 퇴장 처리
    final pendingPostId = prefs.getString('pending_unaccepted_party_post_id');
    final pendingUserId = prefs.getString('pending_unaccepted_party_user_id');
    final pendingShownMs = prefs.getInt('pending_unaccepted_party_shown_ms') ?? 0;
    if (pendingPostId != null && pendingPostId.isNotEmpty && pendingShownMs > 0) {
      final enforcedUntilMs = pendingShownMs + const Duration(minutes: 5).inMilliseconds;
      if (enforcedUntilMs > maxUntilMs) {
        maxUntilMs = enforcedUntilMs;
        await prefs.setInt('party_skip_cooldown_until_ms', enforcedUntilMs);
        if (pendingUserId != null && pendingUserId.isNotEmpty) {
          await prefs.setInt('party_skip_cooldown_until_$pendingUserId', enforcedUntilMs);
          unawaited(
            AppFirebaseService.instance.savePartySkipCooldown(
              pendingUserId,
              DateTime.fromMillisecondsSinceEpoch(enforcedUntilMs),
            ),
          );
        }
      }
      if (pendingUserId != null && pendingUserId.isNotEmpty) {
        unawaited(AppFirebaseService.instance.leaveRidePost(pendingPostId, pendingUserId));
      }
      await prefs.remove('pending_unaccepted_party_post_id');
      await prefs.remove('pending_unaccepted_party_user_id');
      await prefs.remove('pending_unaccepted_party_shown_ms');
    }

    if (maxUntilMs > DateTime.now().millisecondsSinceEpoch) {
      gPartySkipCooldownUntil = DateTime.fromMillisecondsSinceEpoch(maxUntilMs);
    } else {
      gPartySkipCooldownUntil = null;
    }
  } catch (e) {
    debugPrint('Error loading match penalty state: $e');
  }
}

Future<void> markPendingPartyAcceptance(String postId, String userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_unaccepted_party_post_id', postId);
    await prefs.setString('pending_unaccepted_party_user_id', userId);
    await prefs.setInt('pending_unaccepted_party_shown_ms', DateTime.now().millisecondsSinceEpoch);
  } catch (_) {}
}

Future<void> clearPendingPartyAcceptance() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_unaccepted_party_post_id');
    await prefs.remove('pending_unaccepted_party_user_id');
    await prefs.remove('pending_unaccepted_party_shown_ms');
  } catch (_) {}
}

Future<void> applyPartySkipCooldown({
  String? postIdToLeave,
  String? userId,
  Duration duration = const Duration(minutes: 5),
}) async {
  final until = DateTime.now().add(duration);
  gPartySkipCooldownUntil = until;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_unaccepted_party_post_id');
    await prefs.remove('pending_unaccepted_party_user_id');
    await prefs.remove('pending_unaccepted_party_shown_ms');
    await prefs.setInt('party_skip_cooldown_until_ms', until.millisecondsSinceEpoch);
    final targetUid = userId ?? gCurrentUser?.id;
    if (targetUid != null && targetUid.isNotEmpty) {
      await prefs.setInt('party_skip_cooldown_until_$targetUid', until.millisecondsSinceEpoch);
      unawaited(AppFirebaseService.instance.savePartySkipCooldown(targetUid, until));
      if (postIdToLeave != null && postIdToLeave.isNotEmpty) {
        unawaited(AppFirebaseService.instance.leaveRidePost(postIdToLeave, targetUid));
      }
    }
  } catch (e) {
    debugPrint('Error applying skip cooldown: $e');
  }
}

// ⏰ 모집글 작성 가능 시간 (07:00 ~ 익일 02:00) 체크
bool isWritingHoursAllowed() {
  if (gBypassWritingHoursForQA) return true;
  final now = DateTime.now();
  // 새벽 02:00 ~ 06:59:59 (새벽 2시~7시)에는 작성 제한
  if (now.hour >= 2 && now.hour < 7) {
    return false;
  }
  return true;
}

// 🔒 현재 로그인 사용자의 진행 중인 활성 모집글 조회 (1인 1글 제한)
RidePost? getMyActivePost() {
  final myNick = gCurrentUser?.nickname ?? '';
  if (myNick.isEmpty) return null;
  return gRidePosts.cast<RidePost?>().firstWhere(
    (p) => p != null && p.authorName == myNick && !p.isExpired && !p.purpose.contains('랜덤'),
    orElse: () => null,
  );
}

/// 🔒 로그인 여부 전역 검증 및 소셜 로그인 유도 모달
bool ensureUserLoggedIn(BuildContext context, {String actionName = '이 기능'}) {
  if (gCurrentUser != null) return true;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Row(
        children: [
          Icon(Icons.lock_rounded, color: Color(0xFF2563EB), size: 24),
          SizedBox(width: 8),
          Text('로그인이 필요합니다', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: Text(
        '$actionName을(를) 이용하시려면 로그인이 필요합니다.\n\n카카오, Apple, Google 소셜 계정으로 3초 만에 안전하게 시작해보세요 🎿',
        style: const TextStyle(fontSize: 13.5, height: 1.45, color: Colors.black87),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('소셜 로그인하기'),
        ),
      ],
    ),
  );
  return false;
}

// ✍️ 안전한 모집글 작성 화면 오픈 핸들러 (로그인 검증 / 새벽시간 제한 / 1인 1글 제한 / 탈주 페널티 전방위 검증)
Future<void> tryOpenWriteRidePostScreen(
  BuildContext context, {
  VoidCallback? onPostCreated,
  String? initialResortName,
}) async {
  // 0. 로그인 여부 확인
  if (!ensureUserLoggedIn(context, actionName: '모집글을 작성')) return;

  // 1. 새벽 글작성 제한 시간대 검사 (02:00 ~ 07:00)
  if (!isWritingHoursAllowed()) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.nightlight_round, color: Color(0xFF6366F1), size: 22),
            SizedBox(width: 8),
            Text('새벽 슬로프 정비 시간', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Text(
          '새벽 02:00 ~ 오전 07:00에는 슬로프 정비 및 안전을 위해 신규 같이타요 모집글 작성이 제한됩니다.\n\n오전 7시부터 작성하실 수 있습니다. ⛷️',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return;
  }

  // 2. 1인 1 활성 모집글 제한 검사
  final activePost = getMyActivePost();
  if (activePost != null) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 22),
            SizedBox(width: 8),
            Text('진행 중인 모집글 안내', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text(
          '\'${activePost.title}\' 모집글이 현재 진행 중입니다.\n\n같이타요는 원활한 매칭을 위해 한 번에 1개의 모집글만 등록할 수 있습니다. 기존 글이 명일 02시에 자동 만료된 후 새 글을 작성하실 수 있습니다.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RidePostDetailScreen(post: activePost)),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('내 모집글 보기'),
          ),
        ],
      ),
    );
    return;
  }

  // 3. 탈주 페널티 검사
  if (gPostBanUntil != null && DateTime.now().isBefore(gPostBanUntil!)) {
    final remaining = gPostBanUntil!.difference(DateTime.now());
    final minutes = remaining.inMinutes + 1;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('모집글 작성 제한', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text(
          '최근 4인 슬로프 파티 대화방에서 퇴장하여 $minutes분 동안 새 모집글 작성이 제한됩니다.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return;
  }

  final result = await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => WriteRidePostScreen(initialResortName: initialResortName)),
  );
  if (result == true) {
    onPostCreated?.call();
  }
}

// -------------------------------------------------------------
// 같이 탔어요 (후기 & 설질 피드) 데이터 모델
// -------------------------------------------------------------

class RideReview {
  final String id;
  final String authorName;
  final String resortName;
  final String snowCondition;
  final int rating;
  final String content;
  final List<String> photoLabels;
  final List<String> tags;
  final DateTime createdAt;
  int likeCount;
  bool isLiked;
  final int commentCount;
  final String? authorUid;
  final bool isAuthor;

  // 🚨 실시간 신고 및 3회 누적 자동 블라인드
  int reportCount;
  bool isBlinded;
  List<String> reportedUserIds;

  RideReview({
    required this.id,
    required this.authorName,
    this.authorUid,
    this.isAuthor = false,
    required this.resortName,
    required this.snowCondition,
    this.rating = 5,
    required this.content,
    this.photoLabels = const [],
    this.tags = const [],
    required this.createdAt,
    this.likeCount = 0,
    this.isLiked = false,
    this.commentCount = 0,
    this.reportCount = 0,
    this.isBlinded = false,
    List<String>? reportedUserIds,
  }) : reportedUserIds = reportedUserIds ?? [];

  // 🛡️ Apple Guideline 1.2: 로컬 피드 즉시 숨김(Immediate Removal) 및 신고 즉시 숨김
  bool get shouldHide =>
      isBlinded ||
      reportCount >= 3 ||
      (gCurrentUser != null && reportedUserIds.contains(gCurrentUser!.id)) ||
      gHiddenContentIds.contains(id);
}

// -------------------------------------------------------------
// ❄️ 실시간 슬로프 설질 한줄평 모델
// -------------------------------------------------------------

class LiveSnowComment {
  final String id;
  final String resortId;
  final String resortName;
  final String authorName;
  final String? authorUid;
  final String content;
  final String snowCondition;
  final String snowConditionEmoji;
  final DateTime createdAt;
  int likes;
  List<String> likedUserNames;
  int reportCount;
  List<String> reportedUserIds;
  bool isBlinded;

  LiveSnowComment({
    required this.id,
    required this.resortId,
    required this.resortName,
    required this.authorName,
    this.authorUid,
    required this.content,
    required this.snowCondition,
    required this.snowConditionEmoji,
    required this.createdAt,
    this.likes = 0,
    List<String>? likedUserNames,
    this.reportCount = 0,
    List<String>? reportedUserIds,
    this.isBlinded = false,
  })  : likedUserNames = likedUserNames ?? [],
        reportedUserIds = reportedUserIds ?? [];

  // 🛡️ Apple Guideline 1.2: 로컬 피드 즉시 숨김(Immediate Removal)
  bool get shouldHide =>
      isBlinded ||
      reportCount >= 3 ||
      (gCurrentUser != null && reportedUserIds.contains(gCurrentUser!.id)) ||
      gHiddenContentIds.contains(id);
}

// -------------------------------------------------------------
// 🛡️ 금칙어 & 외부 링크 실시간 자동 필터링 서비스 (Apple Guideline 1.2)
// -------------------------------------------------------------

class ContentFilterService {
  // 음란/도박/불법 대출/욕설 및 비방 금칙어 목록
  static const List<String> _bannedKeywords = [
    '조건만남', '성인용품', '출장샵', '원나잇', '애인대행', '유흥', '섹스', '야동', '오프녀',
    '바카라', '카지노', '사설토토', '토토사이트', '릴게임', '홀덤펍광고', '불법대출', '코인리딩',
    '고수익알바', '입금요구', '몸캠', '비아그라', '마약', '대마',
    'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'dick', 'pussy', 'slut', 'cunt',
    '씨발', '시발', '병신', '지랄', '개새끼', '존나', '좆', '새끼', '미친년', '미친놈', '등신', '호구',
  ];

  // 외부 링크 및 연락처 패턴
  static final RegExp _phoneRegex = RegExp(r'01[0-9]-?[0-9]{3,4}-?[0-9]{4}|010\s?[0-9]{4}\s?[0-9]{4}');
  static final RegExp _urlRegex = RegExp(r'https?:\/\/[^\s]+|t\.me\/|open\.kakao\.com');
  static const List<String> _externalContactKeywords = [
    '카톡id', '카카오톡id', '라인id', '텔레그램', '오픈카톡', '오픈채팅', 't.me/', 'open.kakao',
  ];

  /// 텍스트 검증: 금칙어 또는 외부 링크가 포함되어 있으면 사유 반환, 정상일 경우 null 반환
  static String? validate(String text) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    // 1. 금칙어 검사
    for (final word in _bannedKeywords) {
      if (text.contains(word)) {
        return '부적절한 단어("$word")가 포함되어 있어 등록할 수 없습니다.';
      }
    }

    // 2. 외부 연락처 키워드 검사
    for (final contact in _externalContactKeywords) {
      if (lower.contains(contact.toLowerCase())) {
        return '외부 메신저/연락처("$contact") 유도는 안전 정책상 제한됩니다.';
      }
    }

    // 3. 휴대폰 번호 정규식 검사
    if (_phoneRegex.hasMatch(text)) {
      return '개인정보 보호를 위해 전화번호 노출은 제한됩니다. 안전한 인앱 대화방을 이용해주세요.';
    }

    // 4. URL 링크 정규식 검사
    if (_urlRegex.hasMatch(text)) {
      return '외부 웹사이트 링크는 보안 정책상 등록할 수 없습니다.';
    }

    return null;
  }
}

// -------------------------------------------------------------
// 🚨 공통 신고 다이얼로그 (3회 누적 시 자동 블라인드)
// -------------------------------------------------------------

void showReportContentDialog({
  required BuildContext context,
  required String targetType, // '모집글' or '후기'
  required String targetAuthor,
  required int currentReportCount,
  required Function(String reason) onReportSuccess,
}) {
  String selectedReason = '광고 / 상업적 홍보';
  final reasons = [
    '광고 / 상업적 홍보',
    '음란물 / 선정적 게시글',
    '외부 연락처 / 불법 링크 공유',
    '욕설 / 비하 / 불쾌한 언행',
    '낚시 / 도배 / 기타 비매너',
  ];

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.flag_rounded, color: Colors.red, size: 22),
                const SizedBox(width: 8),
                Text('$targetType 신고하기', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('작성자: $targetAuthor', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  const Text('신고 사유를 선택해주세요:', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...reasons.map((r) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r, style: const TextStyle(fontSize: 13)),
                    value: r,
                    groupValue: selectedReason,
                    activeColor: const Color(0xFF2563EB),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedReason = val);
                      }
                    },
                  )),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, color: Colors.red, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '🛡️ 안전 정책 안내 (Apple Guideline 1.2)\n'
                            '• 신고 접수 즉시 회원님의 피드에서 해당 게시글이 즉시 숨김(삭제) 처리됩니다.\n'
                            '• 접수된 신고는 24시간 이내에 관리자가 전수 검토하여 부적절한 콘텐츠를 영구 삭제하고, 불량 이용자는 무관용 원칙(Zero-Tolerance)에 따라 영구 퇴출(계정 영구 정지) 조치합니다.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF7F1D1D), height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  onReportSuccess(selectedReason);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('신고 접수'),
              ),
            ],
          );
        },
      );
    },
  );
}

// -------------------------------------------------------------
// 국내 3대 스키장 (곤지암, 비발디파크, 모나용평)
// -------------------------------------------------------------

const List<SkiResort> kSkiResorts = [
  SkiResort(
    id: 'gonjiam',
    name: '곤지암리조트 (광주)',
    shortName: '곤지암',
    region: '경기 광주',
    lat: 37.3378,
    lng: 127.2934,
    icon: Icons.snowboarding_rounded,
    themeColor: Color(0xFF1E40AF),
    detailedSlopes: [
      DetailedSlope(name: '하늬', section: '베이스/초급', difficulty: SlopeDifficulty.beginner, length: '460m'),
      DetailedSlope(name: '휘슬', section: '초중급', difficulty: SlopeDifficulty.novice, length: '850m'),
      DetailedSlope(name: '와이낫 (Why Not)', section: '중급', difficulty: SlopeDifficulty.intermediate, length: '750m'),
      DetailedSlope(name: '그램 (Gram)', section: '중급', difficulty: SlopeDifficulty.intermediate, length: '680m'),
      DetailedSlope(name: '윈디 (Windy)', section: '정상/중상급', difficulty: SlopeDifficulty.advanced, length: '1,429m'),
      DetailedSlope(name: '제타 1 (Zeta 1)', section: '정상/상급', difficulty: SlopeDifficulty.expert, length: '980m'),
      DetailedSlope(name: '제타 2 (Zeta 2)', section: '상급', difficulty: SlopeDifficulty.expert, status: SlopeStatus.mogul, length: '850m'),
      DetailedSlope(name: '게일 (Gale)', section: '정상/최상급', difficulty: SlopeDifficulty.extreme, length: '1,050m'),
      DetailedSlope(name: '곤지암 펀파크', section: '파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '400m'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18~22)', '심야 (22~02)'],
    officialWebcamUrl: 'https://www.konjiamresort.co.kr/ski/liveCam.dev',
  ),
  SkiResort(
    id: 'vivaldi',
    name: '비발디파크 (홍천)',
    shortName: '비발디',
    region: '강원 홍천',
    lat: 37.6449,
    lng: 127.6837,
    icon: Icons.downhill_skiing_rounded,
    themeColor: Color(0xFF7C3AED),
    detailedSlopes: [
      DetailedSlope(name: '발라드 (Ballad)', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '480m', mapX: 0.57, mapY: 0.54),
      DetailedSlope(name: '블루스 (Blues)', section: '초심 구역', difficulty: SlopeDifficulty.beginner, length: '350m', mapX: 0.92, mapY: 0.56),
      DetailedSlope(name: '재즈 (Jazz)', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '900m', mapX: 0.31, mapY: 0.52),
      DetailedSlope(name: '레게 (Reggae)', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '570m', mapX: 0.32, mapY: 0.35),
      DetailedSlope(name: '클래식 (Classic)', section: '중상급 구역', difficulty: SlopeDifficulty.advanced, length: '750m', mapX: 0.31, mapY: 0.20),
      DetailedSlope(name: '락 (Rock)', section: '최상급 구역', difficulty: SlopeDifficulty.extreme, length: '590m', mapX: 0.40, mapY: 0.29),
      DetailedSlope(name: '테크노 1 (Techno 1)', section: '중상급 구역', difficulty: SlopeDifficulty.advanced, length: '800m', mapX: 0.62, mapY: 0.19),
      DetailedSlope(name: '펑키 (Funky)', section: '중상급 구역', difficulty: SlopeDifficulty.advanced, status: SlopeStatus.closed, length: '550m', mapX: 0.60, mapY: 0.30),
      DetailedSlope(name: '테크노 2 (Techno 2)', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '650m', mapX: 0.74, mapY: 0.42),
      DetailedSlope(name: '힙합 (Hiphop)', section: '중상급 구역', difficulty: SlopeDifficulty.advanced, length: '620m', mapX: 0.79, mapY: 0.37),
      DetailedSlope(name: 'BMW 레이싱 코스', section: '레이싱 구역', difficulty: SlopeDifficulty.expert, length: '500m', mapX: 0.88, mapY: 0.49),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (18:30~22:30)', '심야 (23:00~03:00)'],
    officialWebcamUrl: 'https://www.sonohotelsresorts.com/skiboard/status',
  ),
  SkiResort(
    id: 'yongpyong',
    name: '모나용평 (평창)',
    shortName: '모나용평',
    region: '강원 평창',
    lat: 37.6440,
    lng: 128.6797,
    icon: Icons.landscape_rounded,
    themeColor: Color(0xFF0D9488),
    detailedSlopes: [
      DetailedSlope(name: '레인보우 파라다이스', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.novice, length: '5,600m'),
      DetailedSlope(name: '레인보우 1 (골드)', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, length: '1,200m'),
      DetailedSlope(name: '레인보우 2', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, length: '1,150m'),
      DetailedSlope(name: '레인보우 3', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, status: SlopeStatus.mogul, length: '1,050m'),
      DetailedSlope(name: '레인보우 4', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, length: '1,300m'),
      DetailedSlope(name: '골드밸리', section: '골드 구역', difficulty: SlopeDifficulty.advanced, length: '1,655m'),
      DetailedSlope(name: '골드파라다이스', section: '골드 구역', difficulty: SlopeDifficulty.intermediate, length: '1,450m'),
      DetailedSlope(name: '골드환타지', section: '골드 구역', difficulty: SlopeDifficulty.advanced, length: '1,200m'),
      DetailedSlope(name: '레드 (Red)', section: '레드/실버 구역', difficulty: SlopeDifficulty.expert, length: '950m'),
      DetailedSlope(name: '뉴레드 (New Red)', section: '레드/실버 구역', difficulty: SlopeDifficulty.expert, length: '850m'),
      DetailedSlope(name: '실버 (Silver)', section: '레드/실버 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '1,000m'),
      DetailedSlope(name: '메가그린 (Mega Green)', section: '베이스 구역', difficulty: SlopeDifficulty.novice, length: '700m'),
      DetailedSlope(name: '핑크 (Pink)', section: '베이스 구역', difficulty: SlopeDifficulty.novice, length: '650m'),
      DetailedSlope(name: '옐로우 (Yellow)', section: '베이스 구역', difficulty: SlopeDifficulty.beginner, length: '550m'),
      DetailedSlope(name: '드래곤 파크', section: '파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '450m'),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (19:00~22:00)'],
    officialWebcamUrl: 'https://www.yongpyong.co.kr/kor/guide/realTimeNews/ypResortWebcam.do',
  ),
  SkiResort(
    id: 'phoenix',
    name: '휘닉스파크 (평창)',
    shortName: '휘닉스',
    region: '강원 평창',
    lat: 37.5815,
    lng: 128.3248,
    icon: Icons.ac_unit_rounded,
    themeColor: Color(0xFF16A34A),
    detailedSlopes: [
      DetailedSlope(name: '불새마루 도도 (Dodo)', section: '불새마루 구역', difficulty: SlopeDifficulty.advanced, length: '1,100m'),
      DetailedSlope(name: '불새마루 듀크 (Duke)', section: '불새마루 구역', difficulty: SlopeDifficulty.intermediate, length: '950m'),
      DetailedSlope(name: '불새마루 키위 (Kiwi)', section: '불새마루 구역', difficulty: SlopeDifficulty.intermediate, length: '750m'),
      DetailedSlope(name: '스패로우 (Sparrow)', section: '불새마루 구역', difficulty: SlopeDifficulty.beginner, length: '920m'),
      DetailedSlope(name: '펭귄 (Penguin)', section: '불새마루 구역', difficulty: SlopeDifficulty.beginner, length: '650m'),
      DetailedSlope(name: '호크 1 (Hawk 1)', section: '불새마루 구역', difficulty: SlopeDifficulty.novice, length: '1,050m'),
      DetailedSlope(name: '호크 2 (Hawk 2)', section: '불새마루 구역', difficulty: SlopeDifficulty.intermediate, length: '800m'),
      DetailedSlope(name: '파노라마 (Panorama)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.novice, length: '2,400m'),
      DetailedSlope(name: '챔피온 (Champion)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.expert, length: '1,000m'),
      DetailedSlope(name: '디지 (Dizzy)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.extreme, length: '850m'),
      DetailedSlope(name: '밸리 (Valley)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.advanced, length: '1,120m'),
      DetailedSlope(name: '환타지아 (Fantasia)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.expert, length: '900m'),
      DetailedSlope(name: '슬로프스타일 (익스트림 파크)', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '600m'),
      DetailedSlope(name: '슈퍼 하프파이프', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '160m'),
      DetailedSlope(name: '펀파크 & 웨이브존', section: '익스트림 파크', difficulty: SlopeDifficulty.novice, status: SlopeStatus.park, length: '450m'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18~22)', '심야 (22~24)'],
    officialWebcamUrl: 'https://phoenixhnr.co.kr/m/page/pyeongchang/guide/operation/sketchMovie',
  ),
  SkiResort(
    id: 'high1',
    name: '하이원리조트 (정선)',
    shortName: '하이원',
    region: '강원 정선',
    lat: 37.2078,
    lng: 128.8354,
    icon: Icons.terrain_rounded,
    themeColor: Color(0xFF6B21A8),
    detailedSlopes: [
      DetailedSlope(name: '빅토리아 1', section: '빅토리아 구역 (백운산 1,340m)', difficulty: SlopeDifficulty.extreme, length: '1,439m'),
      DetailedSlope(name: '빅토리아 2', section: '빅토리아 구역 (백운산 1,340m)', difficulty: SlopeDifficulty.expert, status: SlopeStatus.mogul, length: '1,300m'),
      DetailedSlope(name: '빅토리아 3', section: '빅토리아 구역 (백운산 1,340m)', difficulty: SlopeDifficulty.extreme, status: SlopeStatus.closed, length: '1,150m'),
      DetailedSlope(name: '헤라 1', section: '헤라 구역 (마운틴탑)', difficulty: SlopeDifficulty.intermediate, length: '1,504m'),
      DetailedSlope(name: '헤라 2', section: '헤라 구역 (마운틴탑)', difficulty: SlopeDifficulty.advanced, status: SlopeStatus.mogul, length: '1,230m'),
      DetailedSlope(name: '헤라 3', section: '헤라 구역 (마운틴탑)', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '1,100m'),
      DetailedSlope(name: '아폴로 1', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, length: '1,803m'),
      DetailedSlope(name: '아폴로 2', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, length: '1,250m'),
      DetailedSlope(name: '아폴로 3', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.advanced, length: '1,400m'),
      DetailedSlope(name: '아폴로 4', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, length: '1,550m'),
      DetailedSlope(name: '아폴로 6', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '1,180m'),
      DetailedSlope(name: '아테나 1', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,700m'),
      DetailedSlope(name: '아테나 2', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.novice, length: '1,670m'),
      DetailedSlope(name: '아테나 3', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,200m'),
      DetailedSlope(name: '제우스 1', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '2,329m'),
      DetailedSlope(name: '제우스 2', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,840m'),
      DetailedSlope(name: '제우스 3', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,020m'),
    ],
    availableTimeSlots: ['주간 (09~16)', '오후 (12~16)', '야간 (18~22)'],
    officialWebcamUrl: 'https://www.high1.com/ski/slopeView.do?key=748&mode=p',
  ),
  SkiResort(
    id: 'wellihilli',
    name: '웰리힐리파크 (횡성)',
    shortName: '웰리힐리',
    region: '강원 횡성',
    lat: 37.4877,
    lng: 128.2494,
    icon: Icons.snowshoeing_rounded,
    themeColor: Color(0xFF0F766E),
    detailedSlopes: [
      DetailedSlope(name: '알파 1 (A1)', section: '알파/베이스', difficulty: SlopeDifficulty.beginner, length: '700m'),
      DetailedSlope(name: '알파 2, 3 (A2/A3)', section: '알파/베이스', difficulty: SlopeDifficulty.beginner, length: '600m'),
      DetailedSlope(name: '브라보 1 (B1)', section: '브라보 구역', difficulty: SlopeDifficulty.intermediate, length: '1,100m'),
      DetailedSlope(name: '브라보 2 (B2)', section: '브라보 구역', difficulty: SlopeDifficulty.intermediate, length: '950m'),
      DetailedSlope(name: '에코 1, 2 (E1/E2)', section: '에코 구역', difficulty: SlopeDifficulty.intermediate, length: '900m'),
      DetailedSlope(name: '챌린지 1, 2 (C1/C2)', section: '챌린지 구역', difficulty: SlopeDifficulty.expert, length: '850m'),
      DetailedSlope(name: '챌린지 4, 5 (C4/C5)', section: '챌린지 구역', difficulty: SlopeDifficulty.extreme, status: SlopeStatus.mogul, length: '950m'),
      DetailedSlope(name: '스타익스프레스', section: '관광 롱코스', difficulty: SlopeDifficulty.novice, length: '2,100m'),
      DetailedSlope(name: '웰리 펀파크', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '650m'),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (18:30~22:30)', '심야 (22:30~24:00)'],
    officialWebcamUrl: 'https://m.wellihillipark.com/customer/webcam',
  ),
  SkiResort(
    id: 'jisan',
    name: '지산포레스트 (이천)',
    shortName: '지산',
    region: '경기 이천',
    lat: 37.2144,
    lng: 127.3486,
    icon: Icons.forest_rounded,
    themeColor: Color(0xFF16A34A),
    detailedSlopes: [
      DetailedSlope(name: '1번 슬로프', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '950m'),
      DetailedSlope(name: '1-1번 슬로프', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '300m'),
      DetailedSlope(name: '2번 슬로프 (오렌지)', section: '초중급 구역', difficulty: SlopeDifficulty.novice, length: '700m'),
      DetailedSlope(name: '3번 슬로프 (뉴오렌지)', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '900m'),
      DetailedSlope(name: '5번 슬로프 (구 블루/실버)', section: '상급 구역', difficulty: SlopeDifficulty.advanced, length: '1,100m'),
      DetailedSlope(name: '6번 슬로프', section: '상급 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '800m'),
      DetailedSlope(name: '7번 슬로프 (구 블랙)', section: '최상급 구역', difficulty: SlopeDifficulty.extreme, length: '950m'),
      DetailedSlope(name: '지산 익스트림 파크', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '500m'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18:30~23:00)', '심야 (23:00~02:00)'],
    officialWebcamUrl: 'https://www.jisanresort.co.kr/m/ski/slopes/webcam.asp',
  ),
  SkiResort(
    id: 'o2',
    name: '오투리조트 (태백)',
    shortName: '오투',
    region: '강원 태백',
    lat: 37.1772,
    lng: 128.9489,
    icon: Icons.cloud_rounded,
    themeColor: Color(0xFF0284C7),
    detailedSlopes: [
      DetailedSlope(name: '드림 1, 2 (Dream)', section: '드림 구역', difficulty: SlopeDifficulty.beginner, length: '1,100m'),
      DetailedSlope(name: '해피 (Happy)', section: '해피 구역', difficulty: SlopeDifficulty.novice, length: '2,150m'),
      DetailedSlope(name: '글로리 1, 2 (Glory)', section: '글로리 구역', difficulty: SlopeDifficulty.intermediate, length: '1,400m'),
      DetailedSlope(name: '챌린지 (Challenge)', section: '챌린지 구역', difficulty: SlopeDifficulty.expert, length: '900m'),
      DetailedSlope(name: '패션 (Passion)', section: '상급 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '750m'),
    ],
    availableTimeSlots: ['주간 (09~16:30)', '오후 (12:30~16:30)', '야간 (18~21:30)'],
    officialWebcamUrl: 'https://www.o2resort.com/GDE/webcam.jsp',
  ),
  SkiResort(
    id: 'elysian',
    name: '엘리시안 강촌 (춘천)',
    shortName: '강촌',
    region: '강원 춘천',
    lat: 37.8208,
    lng: 127.5880,
    icon: Icons.park_rounded,
    themeColor: Color(0xFF4B5563),
    detailedSlopes: [
      DetailedSlope(name: '팬더 (Panda)', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '500m'),
      DetailedSlope(name: '래빗 (Rabbit)', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '350m'),
      DetailedSlope(name: '드래곤 (Dragon)', section: '초중급 구역', difficulty: SlopeDifficulty.novice, length: '1,050m'),
      DetailedSlope(name: '디어 (Deer)', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '900m'),
      DetailedSlope(name: '퓨마 (Puma)', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '750m'),
      DetailedSlope(name: '페가수스 (Pegasus)', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '850m'),
      DetailedSlope(name: '강촌 익스트림 파크', section: '파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '400m'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18:30~22:30)', '심야 (22:30~03:00)'],
    officialWebcamUrl: 'https://www.elysian.co.kr/about-gangchon/ski#guide-to-using-slopes',
  ),
  SkiResort(
    id: 'muju',
    name: '무주 덕유산 (무주)',
    shortName: '무주',
    region: '전북 무주',
    lat: 35.8899,
    lng: 127.7417,
    icon: Icons.filter_hdr_rounded,
    themeColor: Color(0xFF0284C7),
    detailedSlopes: [
      DetailedSlope(name: '실크로드 상단', section: '설천봉 (1,520m)', difficulty: SlopeDifficulty.novice, length: '3,100m'),
      DetailedSlope(name: '실크로드 하단', section: '설천봉 (1,520m)', difficulty: SlopeDifficulty.novice, length: '3,000m'),
      DetailedSlope(name: '루키힐', section: '만선베이스', difficulty: SlopeDifficulty.intermediate, length: '1,200m'),
      DetailedSlope(name: '커넥션', section: '만선베이스', difficulty: SlopeDifficulty.beginner, length: '800m'),
      DetailedSlope(name: '레이더스 상단', section: '만선봉 정상', difficulty: SlopeDifficulty.extreme, length: '950m'),
      DetailedSlope(name: '레이더스 하단', section: '만선봉 정상', difficulty: SlopeDifficulty.expert, length: '800m'),
      DetailedSlope(name: '프리폴', section: '설천 구역', difficulty: SlopeDifficulty.expert, length: '750m'),
      DetailedSlope(name: '야마가', section: '만선 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.mogul, length: '850m'),
      DetailedSlope(name: '미뉴에트 / 모차르트', section: '설천봉 능선', difficulty: SlopeDifficulty.expert, length: '1,000m'),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (18:30~22:00)'],
    officialWebcamUrl: 'https://www.mdysresort.com/guide/webcam.asp',
  ),
  SkiResort(
    id: 'alpensia',
    name: '알펜시아 (평창)',
    shortName: '알펜시아',
    region: '강원 평창',
    lat: 37.6542,
    lng: 128.6713,
    icon: Icons.terrain_rounded,
    themeColor: Color(0xFFD97706),
    detailedSlopes: [
      DetailedSlope(name: '알파 (Alpha)', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '650m', mapX: 0.88, mapY: 0.44),
      DetailedSlope(name: '브라보 (Bravo)', section: '초중급 구역', difficulty: SlopeDifficulty.novice, length: '950m', mapX: 0.85, mapY: 0.27),
      DetailedSlope(name: '찰리 (Charlie)', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '1,100m', mapX: 0.60, mapY: 0.42),
      DetailedSlope(name: '델타 (Delta)', section: '상급 구역', difficulty: SlopeDifficulty.advanced, length: '850m', mapX: 0.39, mapY: 0.51),
      DetailedSlope(name: '에코 (Echo)', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '750m', mapX: 0.26, mapY: 0.51),
      DetailedSlope(name: '폭스트롯 (Foxtrot)', section: '최상급 구역', difficulty: SlopeDifficulty.extreme, length: '600m', mapX: 0.08, mapY: 0.44),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (18:30~22:00)'],
    officialWebcamUrl: 'https://www.alpensia.com/guide/web-cam.do',
  ),
  SkiResort(
    id: 'oakvalley',
    name: '오크밸리 (원주)',
    shortName: '오크밸리',
    region: '강원 원주',
    lat: 37.4045,
    lng: 127.8188,
    icon: Icons.nature_people_rounded,
    themeColor: Color(0xFF0369A1),
    detailedSlopes: [
      DetailedSlope(name: 'I 슬로프', section: '초심 구역', difficulty: SlopeDifficulty.beginner, length: '500m'),
      DetailedSlope(name: 'H 슬로프', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '600m'),
      DetailedSlope(name: 'A 슬로프', section: '초중급 구역', difficulty: SlopeDifficulty.novice, length: '1,400m'),
      DetailedSlope(name: 'B 슬로프', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '1,100m'),
      DetailedSlope(name: 'C 슬로프 (펀파크)', section: '중급/파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '850m'),
      DetailedSlope(name: 'D 슬로프', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '900m'),
      DetailedSlope(name: 'D-1 슬로프', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '650m'),
      DetailedSlope(name: 'E 슬로프', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '750m'),
      DetailedSlope(name: 'F 슬로프', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '800m'),
      DetailedSlope(name: 'G 슬로프', section: '초중급 구역', difficulty: SlopeDifficulty.novice, length: '950m'),
    ],
    availableTimeSlots: ['주간 (09~16:30)', '오후 (12:30~16:30)', '야간 (18~22:30)'],
    officialWebcamUrl: 'https://oakvalley.co.kr/ski/introduction/realtime',
  ),
];

// -------------------------------------------------------------
// 실시간 날씨 API 서비스 (Open-Meteo 무료 글로벌 날씨 연동)
// -------------------------------------------------------------

class WeatherService {
  static final Map<String, ResortWeather> _cache = {};

  static Future<ResortWeather?> fetchWeather(SkiResort resort) async {
    if (_cache.containsKey(resort.id)) {
      return _cache[resort.id];
    }

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${resort.lat}&longitude=${resort.lng}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,snowfall_sum&timezone=Asia%2FSeoul',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final weather = ResortWeather.fromJson(data);
        _cache[resort.id] = weather;
        return weather;
      }
    } catch (_) {
      // 네트워크 오프라인 또는 오류 시
      return null;
    }

    return null;
  }
}

// -------------------------------------------------------------
// 전역 반응형 상태 (Firestore 실시간 스트림과 직접 바인딩)
// -------------------------------------------------------------

final ValueNotifier<List<RidePost>> gRidePostsNotifier = ValueNotifier<List<RidePost>>([]);
List<RidePost> get gRidePosts => gRidePostsNotifier.value;
set gRidePosts(List<RidePost> posts) {
  gRidePostsNotifier.value = List<RidePost>.from(posts);
}

final ValueNotifier<List<RideReview>> gRideReviewsNotifier = ValueNotifier<List<RideReview>>([]);
List<RideReview> get gRideReviews => gRideReviewsNotifier.value;
set gRideReviews(List<RideReview> reviews) {
  gRideReviewsNotifier.value = List<RideReview>.from(reviews);
}

// -------------------------------------------------------------
// -------------------------------------------------------------
// 메인 화면 (4개 탭)
// -------------------------------------------------------------

class MainScreen extends StatefulWidget {
  final int initialIndex;
  final int initialHubSubTab;
  const MainScreen({super.key, this.initialIndex = 0, this.initialHubSubTab = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  late int _hubSubTabIndex;
  StreamSubscription<List<RidePost>>? _postsSubscription;
  StreamSubscription<List<RideReview>>? _reviewsSubscription;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _hubSubTabIndex = widget.initialHubSubTab;
    // 🌐 실시간 모집글 스트림 구독 (실제 Firestore 데이터만 연동)
    _postsSubscription = AppFirebaseService.instance.streamRidePosts().listen((posts) {
      if (mounted) {
        setState(() {
          gRidePosts = posts;
        });
      }
    });

    // 🌐 실시간 설질 후기 피드 스트림 구독 (실제 Firestore 데이터만 연동)
    _reviewsSubscription = AppFirebaseService.instance.streamReviews().listen((reviews) {
      if (mounted) {
        setState(() {
          gRideReviews = reviews;
        });
      }
    });

    // 🔔 기기 간 실시간 푸시 알림 리스너 시작 (상대방 알림만 수신)
    _startOrUpdateNotificationListener();
    gCurrentUserNotifier.addListener(_startOrUpdateNotificationListener);

    // 🛡️ Apple Guideline 1.2: 앱 최초 실행 시 EULA 및 무관용(Zero-Tolerance) 원칙 명시적 동의 모달
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunchEulaConsent();
      _checkDailyAttendance();
    });
  }

  Future<void> _checkFirstLaunchEulaConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasAgreed = prefs.getBool('has_agreed_to_eula_v1') ?? false;
      if (!hasAgreed && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Row(
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFF2563EB), size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text('커뮤니티 안전 정책 & EULA 동의', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                            SizedBox(width: 6),
                            Text(
                              '무관용 원칙 (Zero-Tolerance Policy)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B)),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          '같이타요는 만 19세(18+) 성인 라이더 전용 커뮤니티입니다. 타인에 대한 욕설, 비방, 음란물, 불법 정보 게시 시 사전 경고 없이 즉각 삭제되며 해당 이용자는 영구 이용 정지(계정 차단) 조치됩니다.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF7F1D1D), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '1. 1터치 즉시 신고 및 차단 시스템 운영\n'
                    '2. 실시간 비속어 및 유해 링크 자동 필터링\n'
                    '3. 접수된 모든 신고는 24시간 이내 관리자 신속 검토 및 조치\n'
                    '4. 차단한 사용자의 모든 콘텐츠는 화면에서 즉시 영구 배제',
                    style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => showAppTermsDialog(context),
                    child: const Text(
                      '📜 서비스 이용약관(EULA) 전문 확인하기 >',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () async {
                    await prefs.setBool('has_agreed_to_eula_v1', true);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('동의하고 시작하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error checking EULA consent: $e');
    }
  }

  Future<void> _checkDailyAttendance() async {
    final awarded = await AppFirebaseService.instance.checkAndAwardDailyAttendance();
    if (awarded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: const Color(0xFF1E3A8A),
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('📅', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '오늘 첫 접속 출석체크 완료!',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                    ),
                    Text(
                      '설질 파우더 포인트 +10P 적립 (현재 보유: ${gCurrentUser?.snowPoints ?? 0}P)',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFBFDBFE)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _startOrUpdateNotificationListener() {
    NotificationService.instance.startRealtimeNotificationListener(
      currentNickname: gCurrentUser?.nickname ?? '',
      currentUid: gCurrentUser?.id ?? '',
      getJoinedPostIds: () => gRidePosts.where((p) => p.canAccessChat).map((p) => p.id).toList(),
      getBadgeCount: () => gRidePosts.where((p) => p.canAccessChat).fold<int>(0, (acc, p) => acc + p.unreadCount),
    );
    NotificationService.instance.syncTokenForUser(gCurrentUser?.id);
  }

  @override
  void dispose() {
    gCurrentUserNotifier.removeListener(_startOrUpdateNotificationListener);
    _postsSubscription?.cancel();
    _reviewsSubscription?.cancel();
    super.dispose();
  }

  void _navigateToTab(int tabIndex, {int subTabIndex = 0}) {
    setState(() {
      _currentIndex = tabIndex;
      _hubSubTabIndex = subTabIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onNavigateToTab: _navigateToTab,
      ),
      RideTogetherHubScreen(
        initialSubTabIndex: _hubSubTabIndex,
      ),
      const ResortInfoScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == 3 && gCurrentUser != null) {
            unawaited(AppFirebaseService.instance.refreshUserProfile(gCurrentUser!.id));
          }
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.snowboarding_outlined),
            selectedIcon: Icon(Icons.snowboarding_rounded),
            label: '같이타요',
          ),
          NavigationDestination(
            icon: Icon(Icons.landscape_outlined),
            selectedIcon: Icon(Icons.landscape_rounded),
            label: '스키장 정보',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: '개인설정',
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 탭 1: 홈 화면 (최신 같이타요 목록 + 4인 랜덤매칭 실시간 현황 + 날씨)
// -------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex, {int subTabIndex}) onNavigateToTab;

  const HomeScreen({
    super.key,
    required this.onNavigateToTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, ResortWeather> _weathers = {};
  SkiResort _selectedSnowResort = kSkiResorts.first;

  @override
  void initState() {
    super.initState();
    _loadWeathers();
  }

  Future<void> _loadWeathers() async {
    for (final resort in kSkiResorts) {
      final w = await WeatherService.fetchWeather(resort);
      if (w != null && mounted) {
        setState(() {
          _weathers[resort.id] = w;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RidePost>>(
      valueListenable: gRidePostsNotifier,
      builder: (context, currentPosts, _) {
        final recentPosts = currentPosts.where((post) {
          if (post.purpose.contains('랜덤')) return false;
          if (post.shouldHide) return false;
          // 내 글은 절대 차단되지 않음
          if (post.isAuthor || (gCurrentUser != null && post.authorUid == gCurrentUser!.id)) return true;
          if (post.authorUid != null && post.authorUid!.isNotEmpty &&
              (gCurrentUser?.isUserBlocked(post.authorUid!, uid: post.authorUid) ?? false)) {
            return false;
          }
          if (!post.isAnonymous && (gCurrentUser?.isUserBlocked(post.authorName) ?? false)) {
            return false;
          }
          return true;
        }).toList();

        recentPosts.sort((a, b) {
          final aTime = a.bumpedAt ?? a.createdAt;
          final bTime = b.bumpedAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        });

        final displayedRecentPosts = recentPosts.take(4).toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 1,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.asset(
                    'assets/logos/penguin_board.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '같이타요',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.5,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '26/27 시즌',
                    style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await _loadWeathers();
              if (mounted) setState(() {});
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // -------------------------------------------------------
                  // 0. ❄️ 실시간 설질 • LIVE 피드 카드
                  // -------------------------------------------------------
                  _buildLiveSnowConditionCard(),

                  const SizedBox(height: 20),

                  // -------------------------------------------------------
                  // 1. ⚡️ 초고속 4인 랜덤 매칭 실시간 현황 & 원터치 진입 카드
                  // -------------------------------------------------------
                  _buildRandomMatchingLiveCard(),

                  const SizedBox(height: 26),

                  // -------------------------------------------------------
                  // 2. 🏂 실시간 같이 타요 최신 등록 항목들
                  // -------------------------------------------------------
                  _buildRecentPostsSection(displayedRecentPosts),

                  const SizedBox(height: 26),

                  // -------------------------------------------------------
                  // 3. ❄️ 주요 스키장 실시간 날씨 & 설질 현황
                  // -------------------------------------------------------
                  _buildResortWeatherSection(),

                  const SizedBox(height: 24),

                  // -------------------------------------------------------
                  // 4. ✍️ 원터치 모집글 등록 배너
                  // -------------------------------------------------------
                  _buildWritePostBanner(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // 위젯 0: ❄️ 실시간 설질 • LIVE 피드 카드
  // -------------------------------------------------------------
  Widget _buildLiveSnowConditionCard() {
    final weather = _weathers[_selectedSnowResort.id];
    final bool hasEarnedToday = gCurrentUser?.hasEarnedSnowPointToday ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 상단 헤더 (실시간 설질 배지 + LIVE + 한줄평 작성 버튼)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.ac_unit_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '실시간 설질',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          '• LIVE',
                          style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  if (!AppFirebaseService.isSnowCommentWritable()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF1E293B),
                        content: Row(
                          children: [
                            Icon(Icons.schedule_rounded, color: Colors.amberAccent, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('새벽 슬로프 정비 시간(03:00~08:00)에는 작성이 제한됩니다. 오전 08:00 이후에 이용해주세요! ❄️'),
                            ),
                          ],
                        ),
                      ),
                    );
                    return;
                  }
                  _showWriteLiveSnowCommentDialog();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_note_rounded, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      !AppFirebaseService.isSnowCommentWritable()
                          ? '정비중 (03~08시)'
                          : (hasEarnedToday ? '한줄평 작성 (완료)' : '한줄평 작성'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. 스키장 수평 선택 칩 목록
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: kSkiResorts.map((resort) {
                final isSelected = _selectedSnowResort.id == resort.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _selectedSnowResort = resort;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        resort.shortName,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // 3. 선택된 스키장 정보 바 (날씨 + 스키장 정보 링크)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedSnowResort.name} (${_selectedSnowResort.region}) ${weather != null ? '${weather.iconEmoji} ${weather.temp > 0 ? '+' : ''}${weather.temp.toStringAsFixed(1)}°C (${weather.weatherDesc})' : '❄️ 날씨 정보를 불러올 수 없습니다'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => widget.onNavigateToTab(2),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '스키장 정보',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF2563EB)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 4. 실시간 한줄평 피드 스트림 목록
          StreamBuilder<List<LiveSnowComment>>(
            stream: AppFirebaseService.instance.streamLiveSnowComments(resortId: _selectedSnowResort.id),
            builder: (context, snapshot) {
              final comments = snapshot.data ?? [];

              if (comments.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.ac_unit_rounded, size: 26, color: Colors.blue.shade300),
                      const SizedBox(height: 6),
                      Text(
                        '아직 오늘 등록된 ${_selectedSnowResort.shortName}의 실시간 설질 한줄평이 없습니다.\n첫 한줄평을 남기고 50P를 획득해보세요! ❄️',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ],
                  ),
                );
              }

              final visibleComments = comments.where((c) {
                if (c.shouldHide) return false;
                if (gCurrentUser != null && gCurrentUser!.isUserBlocked(c.authorUid ?? c.authorName)) return false;
                return true;
              }).toList();

              if (visibleComments.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.ac_unit_rounded, size: 26, color: Colors.blue.shade300),
                      const SizedBox(height: 6),
                      Text(
                        '아직 오늘 등록된 ${_selectedSnowResort.shortName}의 실시간 설질 한줄평이 없습니다.\n첫 한줄평을 남기고 50P를 획득해보세요! ❄️',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ],
                  ),
                );
              }

              final displayed = visibleComments.take(3).toList();

              return Column(
                children: displayed.map((comment) {
                  final diff = DateTime.now().difference(comment.createdAt);
                  final timeAgo = diff.inMinutes < 1
                      ? '방금 전'
                      : diff.inMinutes < 60
                          ? '${diff.inMinutes}분 전'
                          : diff.inHours < 24
                              ? '${diff.inHours}시간 전'
                              : '${diff.inDays}일 전';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Text(
                                '${comment.snowConditionEmoji} ${comment.snowCondition}',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              comment.authorName,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const Spacer(),
                            Text(
                              timeAgo,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 16, color: Colors.grey),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'hide',
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility_off_outlined, size: 15, color: Colors.black87),
                                      SizedBox(width: 6),
                                      Text('이 한줄평 피드에서 즉시 숨기기', style: TextStyle(fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag_outlined, size: 15, color: Colors.orange),
                                      SizedBox(width: 6),
                                      Text('한줄평 신고하기 (24h 검토)', style: TextStyle(fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'block',
                                  child: Row(
                                    children: [
                                      Icon(Icons.block_rounded, size: 15, color: Colors.red),
                                      SizedBox(width: 6),
                                      Text('작성자 차단하기', style: TextStyle(fontSize: 12.5, color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (action) {
                                if (action == 'hide') {
                                  setState(() {
                                    hideContentPermanently(comment.id);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      backgroundColor: Color(0xFF1E3A8A),
                                      content: Text('한줄평이 회원님의 피드에서 즉시 숨김(삭제) 처리되었습니다.'),
                                    ),
                                  );
                                } else if (action == 'block') {
                                  _showBlockUserDialog(comment.authorName, targetUid: comment.authorUid);
                                } else if (action == 'report') {
                                  final currentUserId = gCurrentUser?.id ?? 'me';
                                  showReportContentDialog(
                                    context: context,
                                    targetType: '설질 한줄평',
                                    targetAuthor: comment.authorName,
                                    currentReportCount: comment.reportCount,
                                    onReportSuccess: (reason) {
                                      setState(() {
                                        hideContentPermanently(comment.id);
                                        comment.reportedUserIds.add(currentUserId);
                                        comment.reportCount += 1;
                                        if (comment.reportCount >= 3) {
                                          comment.isBlinded = true;
                                        }
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          backgroundColor: Color(0xFF1E3A8A),
                                          content: Text('🚨 신고가 접수되어 피드에서 즉시 숨김 처리되었습니다. (24시간 이내 관리자 검토 후 조치)'),
                                        ),
                                      );
                                    },
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          comment.content,
                          style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showWriteLiveSnowCommentDialog() {
    if (!ensureUserLoggedIn(context, actionName: '설질 한줄평을 작성')) return;

    if (!AppFirebaseService.isSnowCommentWritable()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E293B),
          content: Row(
            children: [
              Icon(Icons.schedule_rounded, color: Colors.amberAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('새벽 슬로프 정비 시간(03:00~08:00)에는 설질 한줄평을 작성할 수 없습니다. 오전 08:00 이후에 이용해주세요! ❄️'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final controller = TextEditingController();
    String selectedCondition = '양호/양설';
    String selectedEmoji = '✨';

    final conditions = [
      {'label': '양호/양설', 'emoji': '✨'},
      {'label': '강설/아이스', 'emoji': '🧊'},
      {'label': '습설/파우더', 'emoji': '❄️'},
      {'label': '슬러시/봄눈', 'emoji': '☀️'},
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.ac_unit_rounded, color: Color(0xFF2563EB), size: 22),
                const SizedBox(width: 8),
                Text(
                  '${_selectedSnowResort.shortName} 설질 한줄평',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFD97706)),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '설질 한줄평 등록 시 50P가 즉시 적립됩니다! ⚡',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 🛡️ Apple Guideline 1.2: 무관용 원칙 EULA 고지 배너
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: Color(0xFFDC2626)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '욕설, 비방, 허위 설질 작성 시 무관용 원칙(Zero-Tolerance)에 따라 24시간 이내 즉시 삭제 및 계정 이용 정지 조치됩니다.',
                            style: TextStyle(fontSize: 10.5, color: Color(0xFF991B1B), height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('설질 상태 선택', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: conditions.map((item) {
                      final isSel = selectedCondition == item['label'];
                      return ChoiceChip(
                        label: Text('${item['emoji']} ${item['label']}'),
                        selected: isSel,
                        selectedColor: const Color(0xFF2563EB),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Colors.white : Colors.black87,
                        ),
                        visualDensity: VisualDensity.compact,
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              selectedCondition = item['label']!;
                              selectedEmoji = item['emoji']!;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('한줄평 내용', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: '오늘의 ${_selectedSnowResort.shortName} 설질을 한 줄로 공유해주세요 (예: 아이스 살짝 있으나 탈만함)',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('한줄평 내용을 입력해주세요.')),
                    );
                    return;
                  }

                  // 🛡️ 실시간 비속어/유해 콘텐츠 자동 필터링 (Apple Guideline 1.2)
                  final filterError = ContentFilterService.validate(text);
                  if (filterError != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red.shade800,
                        content: Text('⚠️ $filterError'),
                      ),
                    );
                    return;
                  }

                  final newComment = LiveSnowComment(
                    id: '',
                    resortId: _selectedSnowResort.id,
                    resortName: _selectedSnowResort.name,
                    authorName: gCurrentUser?.nickname ?? '익명의 라이더',
                    authorUid: gCurrentUser?.id,
                    content: text,
                    snowCondition: selectedCondition,
                    snowConditionEmoji: selectedEmoji,
                    createdAt: DateTime.now(),
                  );

                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(dialogCtx);
                  final awarded = await AppFirebaseService.instance.addLiveSnowComment(newComment);

                  if (!mounted) return;
                  if (awarded) {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1E3A8A),
                        content: Row(
                          children: [
                            const Icon(Icons.bolt_rounded, color: Colors.amber, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('🎉 [${_selectedSnowResort.shortName}] 설질 한줄평이 등록되고 50P가 적립되었습니다!'),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1E293B),
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('✅ [${_selectedSnowResort.shortName}] 설질 한줄평이 등록되었습니다. (오늘 설질 포인트는 이미 적립되었습니다)'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('등록'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBlockUserDialog(String nickname, {String? targetUid}) {
    final blockTarget = (targetUid != null && targetUid.isNotEmpty) ? targetUid : nickname;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('사용자 차단', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('\'$nickname\' 님을 차단하시겠습니까?\n\n차단 시 해당 사용자가 작성한 모든 글과 한줄평이 목록에서 즉시 숨김 처리됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (gCurrentUser != null) {
                  gCurrentUser!.blockUser(blockTarget);
                  AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  content: Text('\'$nickname\' 님을 차단했습니다. 목록에서 즉시 숨김 처리되었습니다.'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('차단하기'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 위젯 1: 랜덤 매칭 실시간 현황 카드
  // -------------------------------------------------------------
  Widget _buildRandomMatchingLiveCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.shade400.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300.withValues(alpha: 0.5), width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, color: Colors.amber, size: 16),
                SizedBox(width: 4),
                Text(
                  '실시간 4인 슬로프 파티',
                  style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '지금 슬로프라면?\n같은 스키장 4인 파티 매칭!',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.3,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '스키장을 선택하면 라이딩 성향이 맞는 메이트들의 프로필을 확인하고 동행 파티에 합류할 수 있습니다.',
            style: TextStyle(fontSize: 13, color: Colors.blue.shade100, height: 1.4),
          ),
          const SizedBox(height: 18),

          // 매칭 시작 버튼
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (!ensureUserLoggedIn(context, actionName: '4인 슬로프 파티')) return;
                widget.onNavigateToTab(1, subTabIndex: 1); // 같이 타요 > 파티 매칭 탭으로 이동
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E3A8A),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.groups_rounded, size: 20, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Text(
                    '4인 슬로프 파티 찾기 →',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 위젯 2: 같이 타요 최신 등록 항목 섹션
  // -------------------------------------------------------------
  Widget _buildRecentPostsSection(List<RidePost> posts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '실시간 같이타요 모집 🏂',
                  style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  '새로 올라온 슬로프 메이트 모집글',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                widget.onNavigateToTab(1, subTabIndex: 0); // 같이 타요 목록 탭으로 이동
              },
              child: const Row(
                children: [
                  Text('전체보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                  Icon(Icons.chevron_right, size: 18, color: Color(0xFF2563EB)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (posts.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Text('현재 등록된 모집글이 없습니다.\n첫 번째 메이트 모집글을 올려보세요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          Column(
            children: posts.map((post) => _buildPostCard(post)).toList(),
          ),
      ],
    );
  }

  Widget _buildPostCard(RidePost post) {
    final isRandom = post.purpose.contains('랜덤');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1.2),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isRandom ? ChatRoomScreen(post: post) : RidePostDetailScreen(post: post),
            ),
          ).then((_) {
            if (mounted) setState(() {});
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 메타 행 (스키장 배지, 일시, 인원)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isRandom ? Colors.purple.shade50 : const Color(0xFF2563EB).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      post.resortName.split(' ')[0],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isRandom ? Colors.purple.shade700 : const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${post.dateText} • ${post.timeSlot}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: post.isFull ? Colors.grey.shade100 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${post.currentMembers}/${post.maxMembers + 1}명',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: post.isFull ? Colors.grey.shade600 : Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 제목
              Text(
                post.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // 태그들 (종목, 스타일, 레벨)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildTag('${post.discipline} • ${post.style}', Colors.blue.shade50, Colors.blue.shade800),
                  _buildTag(post.skillLevel, Colors.grey.shade100, Colors.grey.shade700),
                  if (post.slopes.isNotEmpty)
                    _buildTag(post.slopes.first, Colors.grey.shade100, Colors.grey.shade700),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  // -------------------------------------------------------------
  // 위젯 3: 스키장 실시간 날씨 가로 스크롤
  // -------------------------------------------------------------
  Widget _buildResortWeatherSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '주요 스키장 실시간 날씨 ❄️',
                  style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  '기온 및 설질 상태 실시간 확인',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                widget.onNavigateToTab(2); // 스키장 정보 탭으로 이동
              },
              child: const Row(
                children: [
                  Text('전체 스키장', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                  Icon(Icons.chevron_right, size: 18, color: Color(0xFF2563EB)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: kSkiResorts.length,
            itemBuilder: (context, index) {
              final resort = kSkiResorts[index];
              final weather = _weathers[resort.id];

              return Container(
                width: 140,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 26,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Image.asset(
                            resort.logoAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(resort.icon, color: resort.themeColor, size: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            resort.shortName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          weather != null ? '${weather.iconEmoji} ${weather.temp > 0 ? '+' : ''}${weather.temp.toStringAsFixed(1)}°' : '❄️ --.-°',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
                        ),
                      ],
                    ),
                    Text(
                      weather != null ? '체감 ${weather.apparentTemp.toStringAsFixed(1)}° • ${weather.weatherDesc}' : '날씨 정보를 불러올 수 없습니다',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // 위젯 4: 모집글 올리기 빠른 배너
  // -------------------------------------------------------------
  Widget _buildWritePostBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_note_rounded, color: Color(0xFF2563EB), size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 일정에 맞는 메이트 구하기',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                SizedBox(height: 2),
                Text(
                  '원하는 스키장/시간대로 직접 글을 올려보세요',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              tryOpenWriteRidePostScreen(context, onPostCreated: () {
                if (mounted) setState(() {});
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('글쓰기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 탭 2: 같이 타요 (대묶음 Hub)
// -------------------------------------------------------------
class RideTogetherHubScreen extends StatefulWidget {
  final int initialSubTabIndex;

  const RideTogetherHubScreen({
    super.key,
    this.initialSubTabIndex = 0,
  });

  @override
  State<RideTogetherHubScreen> createState() => _RideTogetherHubScreenState();
}

class _RideTogetherHubScreenState extends State<RideTogetherHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialSubTabIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant RideTogetherHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubTabIndex != widget.initialSubTabIndex) {
      _tabController.animateTo(widget.initialSubTabIndex.clamp(0, 1));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                'assets/logos/penguin_board.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '같이타요',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '동행 허브',
                style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF2563EB),
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: const Color(0xFF2563EB),
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_rounded, size: 16),
                      SizedBox(width: 5),
                      Text('같이타요'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.groups_rounded, size: 16),
                      SizedBox(width: 5),
                      Text('4인 파티 매칭'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          RidePostListView(),
          RandomMatchingView(),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 소묶음 1: 같이 타요 모집글 목록
// -------------------------------------------------------------
class RidePostListView extends StatefulWidget {
  const RidePostListView({super.key});

  @override
  State<RidePostListView> createState() => _RidePostListViewState();
}

class _RidePostListViewState extends State<RidePostListView> {
  String _selectedResort = '전체';
  String _selectedDiscipline = '전체'; // 전체, 스키, 스노보드
  String _selectedTimeSlot = '전체'; // 전체, 주간, 야간, 심야
  bool _onlyRecruiting = false; // 모집 중만 보기 (정원 마감 제외)
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilter =>
      _selectedResort != '전체' ||
      _selectedDiscipline != '전체' ||
      _selectedTimeSlot != '전체' ||
      _onlyRecruiting ||
      _searchKeyword.isNotEmpty;

  void _resetFilters() {
    setState(() {
      _selectedResort = '전체';
      _selectedDiscipline = '전체';
      _selectedTimeSlot = '전체';
      _onlyRecruiting = false;
      _searchKeyword = '';
      _searchController.clear();
      _isSearchOpen = false;
    });
  }

  int _getPostCountForResort(String resortShortName) {
    return gRidePosts.where((post) {
      if (post.purpose.contains('랜덤')) return false;
      if (post.shouldHide) return false;
      if (post.isAuthor || (gCurrentUser != null && post.authorUid == gCurrentUser!.id)) {
        // 내 글은 항상 카운트
      } else {
        if (post.authorUid != null && post.authorUid!.isNotEmpty &&
            (gCurrentUser?.isUserBlocked(post.authorUid!, uid: post.authorUid) ?? false)) {
          return false;
        }
        if (!post.isAnonymous && (gCurrentUser?.isUserBlocked(post.authorName) ?? false)) {
          return false;
        }
      }
      if (resortShortName == '전체') return true;
      return post.resortName.contains(resortShortName);
    }).length;
  }

  List<RidePost> get _myJoinedPosts =>
      gRidePosts.where((p) => p.canAccessChat).toList();

  void _showBlockUserDialog(String nickname, {String? targetUid}) {
    final blockTarget = (targetUid != null && targetUid.isNotEmpty) ? targetUid : nickname;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('사용자 차단', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('\'$nickname\' 님을 차단하시겠습니까?\n\n차단 시 해당 사용자가 작성한 모든 모집글과 후기가 목록에서 즉시 숨김 처리됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (gCurrentUser != null) {
                  gCurrentUser!.blockUser(blockTarget);
                  AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  content: Text('\'$nickname\' 님을 차단했습니다. 목록에서 즉시 숨김 처리되었습니다.'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('차단하기'),
          ),
        ],
      ),
    );
  }

  void _openMyChatRoomsModal() {
    final joined = _myJoinedPosts;
    if (joined.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 참여 중인 대화방이 없습니다. 글을 작성하거나 참가해보세요!')),
      );
      return;
    }

    if (joined.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatRoomScreen(post: joined.first)),
      ).then((_) => setState(() {}));
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.mark_chat_unread_rounded, color: Color(0xFF2563EB), size: 20),
                    SizedBox(width: 8),
                    Text('참여 중인 대화방 목록', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                ...joined.map((post) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF2563EB), size: 18),
                    ),
                    title: Text(post.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1),
                    subtitle: Text('${post.resortName.split(' ')[0]} • ${post.currentMembers}/${post.maxMembers + 1}명', style: const TextStyle(fontSize: 12)),
                    trailing: post.unreadCount > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${post.unreadCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ChatRoomScreen(post: post)),
                      ).then((_) => setState(() {}));
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDisciplineFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('종목 선택', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('전체 종목 보기'),
                trailing: _selectedDiscipline == '전체' ? const Icon(Icons.check_rounded, color: Color(0xFF2563EB)) : null,
                onTap: () {
                  setState(() => _selectedDiscipline = '전체');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Text('🎿', style: TextStyle(fontSize: 22)),
                title: const Text('스키 (인터스키, 프리스키)'),
                trailing: _selectedDiscipline == '스키' ? const Icon(Icons.check_rounded, color: Color(0xFF2563EB)) : null,
                onTap: () {
                  setState(() => _selectedDiscipline = '스키');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Text('🏂', style: TextStyle(fontSize: 22)),
                title: const Text('스노보드 (라이딩, 트릭, 파크)'),
                trailing: _selectedDiscipline == '스노보드' ? const Icon(Icons.check_rounded, color: Color(0xFF2563EB)) : null,
                onTap: () {
                  setState(() => _selectedDiscipline = '스노보드');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTimeSlotFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('시간대 선택', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...['전체', '주간', '야간', '심야'].map((slot) {
                final isSelected = _selectedTimeSlot == slot;
                return ListTile(
                  title: Text(slot == '전체' ? '전체 시간대' : slot),
                  trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFF2563EB)) : null,
                  onTap: () {
                    setState(() => _selectedTimeSlot = slot);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResortChip(String shortName, {bool isHomeBadge = false}) {
    final isSelected = _selectedResort == shortName;
    final count = _getPostCountForResort(shortName);

    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHomeBadge) ...[
            const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
            const SizedBox(width: 2),
          ],
          Text(
            isHomeBadge ? '내 베이스 ($shortName)' : shortName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFF2563EB).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF2563EB),
                ),
              ),
            ),
          ],
        ],
      ),
      backgroundColor: Colors.grey.shade100,
      selectedColor: const Color(0xFF2563EB),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      onSelected: (_) {
        setState(() {
          _selectedResort = shortName;
        });
      },
    );
  }

  Widget _buildSubFilterChip({
    required String label,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB).withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade800,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader() {
    final homeResort = gCurrentUser?.homeResort.split(' ')[0] ?? '';
    final hasHomeResort = homeResort.isNotEmpty && kSkiResorts.any((r) => r.shortName == homeResort || r.name.contains(homeResort));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1행: 검색창이 열려있으면 검색 입력 필드 표시
          if (_isSearchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    const Icon(Icons.search_rounded, size: 18, color: Color(0xFF2563EB)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: '슬로프(5번, 레인보우), 스타일, 닉네임 검색',
                          hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchKeyword = val.trim();
                          });
                        },
                      ),
                    ),
                    if (_searchKeyword.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchKeyword = '';
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          _isSearchOpen = false;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

          // 2행: 스키장(베이스) 탭바 가로 스크롤
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                _buildResortChip('전체'),
                if (hasHomeResort) ...[
                  const SizedBox(width: 6),
                  _buildResortChip(homeResort, isHomeBadge: true),
                ],
                const SizedBox(width: 6),
                ...kSkiResorts.where((r) => r.shortName != homeResort).map((resort) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildResortChip(resort.shortName),
                  );
                }),
              ],
            ),
          ),

          // 3행: 2차 빠른 필터 옵션 바 (종목 / 모집상태 / 시간대 / 검색버튼 / 초기화버튼)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 종목 필터 (전체 / 🎿 스키 / 🏂 스노보드)
                  _buildSubFilterChip(
                    label: _selectedDiscipline == '전체' ? '종목 전체' : _selectedDiscipline == '스키' ? '🎿 스키' : '🏂 스노보드',
                    isSelected: _selectedDiscipline != '전체',
                    icon: Icons.snowboarding_rounded,
                    onTap: _showDisciplineFilterDialog,
                  ),
                  const SizedBox(width: 6),

                  // 모집 중만 보기 토글 칩
                  FilterChip(
                    selected: _onlyRecruiting,
                    showCheckmark: false,
                    avatar: Icon(
                      _onlyRecruiting ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 14,
                      color: _onlyRecruiting ? Colors.white : Colors.grey.shade600,
                    ),
                    label: const Text('모집 중만', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    labelStyle: TextStyle(
                      color: _onlyRecruiting ? Colors.white : Colors.grey.shade800,
                    ),
                    backgroundColor: Colors.grey.shade100,
                    selectedColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: _onlyRecruiting ? Colors.transparent : Colors.grey.shade300,
                      ),
                    ),
                    onSelected: (val) {
                      setState(() {
                        _onlyRecruiting = val;
                      });
                    },
                  ),
                  const SizedBox(width: 6),

                  // 시간대 필터 (전체 / 주간 / 야간 / 심야)
                  _buildSubFilterChip(
                    label: _selectedTimeSlot == '전체' ? '시간대' : _selectedTimeSlot,
                    isSelected: _selectedTimeSlot != '전체',
                    icon: Icons.access_time_rounded,
                    onTap: _showTimeSlotFilterDialog,
                  ),
                  const SizedBox(width: 6),

                  // 검색창 토글 버튼
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSearchOpen = !_isSearchOpen;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isSearchOpen || _searchKeyword.isNotEmpty
                            ? const Color(0xFF2563EB).withValues(alpha: 0.12)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isSearchOpen || _searchKeyword.isNotEmpty
                              ? const Color(0xFF2563EB)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 14,
                            color: _isSearchOpen || _searchKeyword.isNotEmpty
                                ? const Color(0xFF2563EB)
                                : Colors.grey.shade700,
                          ),
                          if (_searchKeyword.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '\'$_searchKeyword\'',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // 활성 필터 초기화 버튼
                  if (_hasActiveFilter) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _resetFilters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 13, color: Colors.red),
                            SizedBox(width: 2),
                            Text('초기화', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilter = _hasActiveFilter;
    final resortName = _selectedResort;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasFilter ? Icons.filter_list_off_rounded : Icons.snowboarding_rounded,
                size: 48,
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? (resortName != '전체' ? '\'$resortName\'에 등록된 모집글이 없습니다' : '선택한 조건의 모집글이 없습니다')
                  : '등록된 같이타요 모집글이 없습니다',
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? (resortName != '전체'
                      ? '내가 먼저 \'$resortName\' 슬로프 메이트를 모집해보세요!'
                      : '필터를 변경하거나 첫 번째 모집글을 올려보세요!')
                  : '내가 원하는 스키장과 시간대를 정해\n첫 번째 슬로프 메이트 모집글을 올려보세요!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasFilter) ...[
                  OutlinedButton.icon(
                    onPressed: _resetFilters,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade800,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('필터 초기화', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  onPressed: () => tryOpenWriteRidePostScreen(
                    context,
                    initialResortName: resortName != '전체' ? resortName : null,
                    onPostCreated: () => setState(() {}),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    resortName != '전체' ? '\'$resortName\' 첫 글 작성' : '첫 모집글 작성하기',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RidePost>>(
      valueListenable: gRidePostsNotifier,
      builder: (context, currentPosts, _) {
        final visiblePosts = currentPosts.where((post) {
          if (post.purpose.contains('랜덤')) return false; // 🚫 4인 랜덤매칭 대화방은 일반 모집글 피드에서 제외
          if (post.shouldHide) return false;
          if (post.isAuthor || (gCurrentUser != null && post.authorUid == gCurrentUser!.id)) {
            // 내 글은 항상 표시
          } else {
            if (post.authorUid != null && post.authorUid!.isNotEmpty &&
                (gCurrentUser?.isUserBlocked(post.authorUid!, uid: post.authorUid) ?? false)) {
              return false;
            }
            if (!post.isAnonymous && (gCurrentUser?.isUserBlocked(post.authorName) ?? false)) {
              return false;
            }
          }

          // 1. 스키장(베이스) 필터
          if (_selectedResort != '전체') {
            if (!post.resortName.contains(_selectedResort)) {
              return false;
            }
          }

          // 2. 종목 필터 (스키 / 스노보드)
          if (_selectedDiscipline != '전체') {
            if (post.discipline != _selectedDiscipline) {
              return false;
            }
          }

          // 3. 모집 상태 필터 (모집 중만 보기)
          if (_onlyRecruiting && post.isFull) {
            return false;
          }

          // 4. 시간대 필터 (주간, 야간, 심야)
          if (_selectedTimeSlot != '전체') {
            if (!post.timeSlot.contains(_selectedTimeSlot)) {
              return false;
            }
          }

          // 5. 검색어 필터 (제목, 슬로프, 본문, 작성자)
          if (_searchKeyword.isNotEmpty) {
            final q = _searchKeyword.toLowerCase();
            final matchTitle = post.title.toLowerCase().contains(q);
            final matchSlopes = post.slopes.any((s) => s.toLowerCase().contains(q));
            final matchContent = post.content.toLowerCase().contains(q);
            final matchAuthor = post.authorName.toLowerCase().contains(q);
            if (!matchTitle && !matchSlopes && !matchContent && !matchAuthor) {
              return false;
            }
          }

          return true;
        }).toList();

        visiblePosts.sort((a, b) {
          final aTime = a.bumpedAt ?? a.createdAt;
          final bTime = b.bumpedAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        });

        final joinedPosts = currentPosts.where((p) => p.canAccessChat).toList();
        final totalUnreadCount = joinedPosts.fold<int>(0, (sum, p) => sum + p.unreadCount);

        return Scaffold(
          body: Column(
            children: [
              _buildFilterHeader(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    final refreshed = await AppFirebaseService.instance.getRidePostsOnce();
                    if (refreshed.isNotEmpty) {
                      gRidePosts = refreshed;
                    }
                    await Future.delayed(const Duration(milliseconds: 300));
                  },
                  child: visiblePosts.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: visiblePosts.length,
                          itemBuilder: (context, index) {
                            final post = visiblePosts[index];
                            return _buildPostCard(post);
                          },
                        ),
                ),
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (joinedPosts.isNotEmpty) ...[
                if (totalUnreadCount > 0)
                  Badge(
                    label: Text('$totalUnreadCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.redAccent,
                    child: FloatingActionButton(
                      heroTag: 'floating_chat_button_hub',
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2563EB),
                      elevation: 4,
                      shape: const CircleBorder(side: BorderSide(color: Color(0xFF2563EB), width: 1.5)),
                      onPressed: _openMyChatRoomsModal,
                      tooltip: '참여 중인 대화방 바로가기',
                      child: const Icon(Icons.chat_bubble_rounded),
                    ),
                  )
                else
                  FloatingActionButton(
                    heroTag: 'floating_chat_button_hub',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2563EB),
                    elevation: 4,
                    shape: const CircleBorder(side: BorderSide(color: Color(0xFF2563EB), width: 1.5)),
                    onPressed: _openMyChatRoomsModal,
                    tooltip: '참여 중인 대화방 바로가기',
                    child: const Icon(Icons.chat_bubble_rounded),
                  ),
                const SizedBox(height: 12),
              ],
              FloatingActionButton.extended(
                heroTag: 'floating_write_button_hub',
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                onPressed: () => tryOpenWriteRidePostScreen(
                  context,
                  initialResortName: _selectedResort != '전체' ? _selectedResort : null,
                  onPostCreated: () => setState(() {}),
                ),
                icon: const Icon(Icons.edit),
                label: const Text('글쓰기', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostCard(RidePost post) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RidePostDetailScreen(post: post)),
          ).then((_) => setState(() {}));
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      post.resortName.split(' ')[0],
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${post.discipline}(${post.style}) • ${post.skillLevel}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  if (post.isAuthor)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('내가 쓴 글', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                    )
                  else if (post.isJoined)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('참여 중', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                    ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: post.isFull ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: post.isFull ? Colors.red.shade200 : Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person, size: 10.5, color: post.isFull ? Colors.red.shade700 : Colors.green.shade700),
                        const SizedBox(width: 1.5),
                        Text(
                          '${post.currentMembers}/${post.maxMembers + 1}명',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: post.isFull ? Colors.red.shade800 : Colors.green.shade800),
                        ),
                      ],
                    ),
                  ),
                  if (!post.isAuthor) ...[
                    const SizedBox(width: 1),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'hide',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_off_outlined, size: 16, color: Colors.black87),
                              SizedBox(width: 8),
                              Text('이 글 피드에서 즉시 숨기기', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(Icons.flag_outlined, size: 16, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('모집글 신고하기 (24h 검토)', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'block',
                          child: Row(
                            children: [
                              Icon(Icons.block_rounded, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('작성자 차단하기', style: TextStyle(fontSize: 13, color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (val) {
                        if (val == 'hide') {
                          setState(() {
                            hideContentPermanently(post.id);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF1E3A8A),
                              content: Text('게시글이 회원님의 피드에서 즉시 숨김(삭제) 처리되었습니다.'),
                            ),
                          );
                        } else if (val == 'block') {
                          _showBlockUserDialog(post.authorName, targetUid: post.authorUid);
                        } else if (val == 'report') {
                          final currentUserId = gCurrentUser?.id ?? 'me';
                          if (post.reportedUserIds.contains(currentUserId)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('이미 신고하신 모집글입니다.')),
                            );
                            return;
                          }
                          showReportContentDialog(
                            context: context,
                            targetType: '모집글',
                            targetAuthor: post.authorName,
                            currentReportCount: post.reportCount,
                            onReportSuccess: (reason) {
                              setState(() {
                                hideContentPermanently(post.id);
                                post.reportCount += 1;
                                post.reportedUserIds.add(currentUserId);
                                if (post.reportCount >= 3) {
                                  post.isBlinded = true;
                                }
                              });
                              if (post.id.isNotEmpty) {
                                AppFirebaseService.instance.reportRidePost(post.id, currentUserId);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF1E3A8A),
                                  content: Text('🚨 신고가 접수되어 피드에서 즉시 숨김 처리되었습니다. (24시간 이내 관리자 검토 후 영구 조치)'),
                                ),
                              );
                            },
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.title,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '슬로프: ${post.slopes.join(', ')}',
                style: TextStyle(fontSize: 12.5, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              if (post.content.isNotEmpty)
                Text(
                  post.content,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${post.dateText} ${post.timeSlot} • ${post.authorName}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (post.isAnonymous) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('익명', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (post.bumpedAt != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Text('⚡ 끌올', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const Text('상세보기 >', style: TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 소묶음 2: 초고속 4인 랜덤 매칭 화면
// -------------------------------------------------------------
class RandomMatchingView extends StatefulWidget {
  const RandomMatchingView({super.key});

  @override
  State<RandomMatchingView> createState() => _RandomMatchingViewState();
}

class _RandomMatchingViewState extends State<RandomMatchingView> with SingleTickerProviderStateMixin {
  SkiResort _selectedResort = kSkiResorts.first;
  bool _isMatching = false;
  int _matchedCount = 1;
  int _elapsedSeconds = 0;
  Timer? _tickerTimer;
  Timer? _cooldownUiTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _queueSubscription;
  StreamSubscription<Map<String, dynamic>?>? _statusSubscription;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<String> _currentQueue = [];

  @override
  void initState() {
    super.initState();
    // 새벽 03:00 ~ 06:00 접속 시 야간 잔여 대기열 자동 플러시
    final now = DateTime.now();
    if (now.hour >= 3 && now.hour < 6) {
      AppFirebaseService.instance.flushAllMatchQueues();
    }
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    loadMatchPenaltyState().then((_) {
      if (mounted) {
        _syncCooldownTimer();
        setState(() {});
      }
    });
    _syncCooldownTimer();
  }

  void _syncCooldownTimer() {
    _cooldownUiTimer?.cancel();
    if (getRemainingSkipCooldown() > Duration.zero) {
      _cooldownUiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {});
        if (getRemainingSkipCooldown() == Duration.zero) {
          timer.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _cooldownUiTimer?.cancel();
    _queueSubscription?.cancel();
    _statusSubscription?.cancel();
    if (_isMatching && gCurrentUser != null) {
      AppFirebaseService.instance.leaveMatchQueue(_selectedResort.id, gCurrentUser!.id);
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _showSkipCooldownDialog(Duration remaining) {
    final totalSec = remaining.inSeconds.clamp(1, 300);
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    final timeStr = min > 0 ? '$min분 $sec초' : '$sec초';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.hourglass_bottom_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('매칭 일시 제한 (5분 페널티)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, color: Colors.orange.shade800, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '남은 제한 시간: $timeStr',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '직전 매칭에서 [다음에 하기]를 선택하셨거나 수락 없이 이탈하여, 반복 매칭 악용 방지를 위해 5분간 재매칭이 제한됩니다.\n\n앱을 종료 후 다시 실행해도 남은 제한 시간은 동일하게 유지됩니다.',
              style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.45),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showDailyLimitExceededDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Row(
            children: [
              Icon(Icons.lock_clock_rounded, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('오늘 매칭 횟수 소진', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '오늘의 4인 파티 매칭 기회(1회)를 모두 사용하셨습니다.',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '무분별한 매칭 방지와 진정성 있는 슬로프 만남을 위해 4인 슬로프 파티 매칭은 1일 1회로 제한됩니다.\n\n매일 자정(00:00)에 다시 충전됩니다.',
                style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.45),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      gDailyRandomMatchRemaining = 1;
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚡️ [테스트용] 오늘의 매칭 기회가 1회 다시 충전되었습니다!')),
                    );
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('테스트용 매칭 횟수 1회 리셋', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                final tabController = DefaultTabController.of(context);
                tabController.animateTo(0);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('일반 같이타요 글 보기'),
            ),
          ],
        );
      },
    );
  }

  void _showMidnightClosedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.nightlight_round, color: Colors.indigo, size: 24),
            SizedBox(width: 8),
            Text('심야 정설 및 휴장 시간', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          '새벽 03:00 ~ 06:00은 슬로프 정설 및 심야 휴장 시간입니다.\n\n안전한 라이딩을 위해 이 시간대에는 슬로프 파티 매칭이 제한됩니다. 오전 슬로프 오픈 시 다시 이용해 주세요 ⛷️',
          style: TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.45),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _handleMidnightShutdown() {
    _cancelMatching(leaveQueue: true);
    // 03:00 정각 전 스키장 대기열 일괄 플러시
    AppFirebaseService.instance.flushAllMatchQueues();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.nightlight_round, color: Colors.indigo, size: 24),
            SizedBox(width: 8),
            Text('심야 운영 마감 (03:00)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          '새벽 03:00 심야 슬로프 운영이 마감되어 모든 매칭 대기열이 종료되었습니다.\n\n매칭 기회는 차감되지 않으며, 오전 슬로프 오픈 시 다시 매칭에 참여하실 수 있습니다 ⛷️',
          style: TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.45),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _startMatching() {
    if (!ensureUserLoggedIn(context, actionName: '4인 슬로프 파티')) return;

    // 0. 🌙 새벽 03:00 ~ 06:00 슬로프 정설/휴장 시간 체크
    final now = DateTime.now();
    if (now.hour >= 3 && now.hour < 6) {
      _showMidnightClosedDialog();
      return;
    }

    // 0-1. ⏱️ '다음에 하기' 거절 페널티 (5분 매칭 제한) 검사
    final remainingCooldown = getRemainingSkipCooldown();
    if (remainingCooldown > Duration.zero) {
      _syncCooldownTimer();
      _showSkipCooldownDialog(remainingCooldown);
      return;
    }

    if (gDailyRandomMatchRemaining <= 0) {
      _showDailyLimitExceededDialog();
      return;
    }

    final currentUser = gCurrentUser;
    if (currentUser == null) return;

    setState(() {
      _isMatching = true;
      _matchedCount = 1;
      _elapsedSeconds = 0;
      _currentQueue.clear();
      _currentQueue.add(currentUser.nickname);
    });

    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
      });

      final tickNow = DateTime.now();
      // 1) ⚡️ 새벽 03:00 정각 세션 종료 감지 시 강제 튕김 및 대기열 플러시
      if (tickNow.hour >= 3 && tickNow.hour < 6) {
        _handleMidnightShutdown();
        return;
      }

      // 2) ⚡️ 15분 (900초) 대기 시간 초과 시 자동 퇴장 및 알림 모달
      if (_elapsedSeconds >= 900) {
        _handleMatchTimeout();
        return;
      }
    });

    // 1. 실제 Firestore 실시간 대기 큐 등록
    AppFirebaseService.instance.joinMatchQueue(
      resortId: _selectedResort.id,
      resortName: _selectedResort.name,
      shortName: _selectedResort.shortName,
      uid: currentUser.id,
      nickname: currentUser.nickname,
    );

    // 2. 대기열 인원 실시간 구독
    _queueSubscription?.cancel();
    _queueSubscription = AppFirebaseService.instance.streamMatchQueue(_selectedResort.id).listen((riders) {
      if (!mounted || !_isMatching) return;
      final myId = currentUser.id;
      final stillInQueue = riders.any((r) => r['uid'] == myId || r['id'] == myId);
      if (!stillInQueue && _elapsedSeconds > 10) {
        _handleMatchTimeout();
        return;
      }
      setState(() {
        _currentQueue.clear();
        for (final r in riders) {
          final nick = r['nickname'] as String? ?? '익명 라이더';
          _currentQueue.add(nick);
        }
        if (!_currentQueue.contains(currentUser.nickname)) {
          _currentQueue.insert(0, currentUser.nickname);
        }
        _matchedCount = _currentQueue.length.clamp(1, 4);
      });
    });

    // 3. 나의 매칭 성사 상태 구독
    _statusSubscription?.cancel();
    _statusSubscription = AppFirebaseService.instance.streamUserMatchStatus(currentUser.id).listen((data) async {
      if (!mounted || !_isMatching || data == null) return;
      if (data['status'] == 'matched' && data['matchedPostId'] != null) {
        final matchedPostId = data['matchedPostId'] as String;
        _cancelMatching(leaveQueue: false);

        // Firestore 실제 매칭 글 조회 (로컬에 없으면 서버에서 직접 조회)
        RidePost? post = gRidePosts.where((p) => p.id == matchedPostId).firstOrNull;
        post ??= await AppFirebaseService.instance.getRidePostById(matchedPostId);
        if (!mounted || post == null) return;
        final validPost = post;

        // 🌟 Apple Guideline 1.2 안전 규정: 대화방 입장 전 상대방 프로필 확인 및 [수락(Accept)] / [거절(Decline)] 선택 모달
        await _showPreChatAcceptanceDialog(validPost);
      }
    });
  }

  // -------------------------------------------------------------
  // 🌟 Apple Guideline 1.2 필수: 대화방 입장 전 프로필 사전 확인 및 수락/거절 모달
  // -------------------------------------------------------------
  Future<void> _showPreChatAcceptanceDialog(RidePost post) async {
    final currentUser = gCurrentUser;
    if (currentUser == null || !mounted) return;

    // 🛡️ 모달이 열린 상태에서 앱을 강제 종료(스와이프 킬)해 페널티를 우회하는 악용 차단
    await markPendingPartyAcceptance(post.id, currentUser.id);

    // 참가자 프로필 비동기 로딩 (서버 + 로컬)
    final participantsList = <UserProfile>[];
    for (int i = 0; i < post.participantUids.length; i++) {
      final uid = post.participantUids[i];
      if (uid == currentUser.id) {
        participantsList.add(currentUser);
      } else {
        UserProfile? prof = await AppFirebaseService.instance.fetchUserProfile(uid);
        prof ??= UserProfile(
          id: uid,
          email: '',
          joinedAt: DateTime.now(),
          nickname: i < post.participantNames.length ? post.participantNames[i] : '라이더 $i',
          homeResort: post.resortName,
          level: '중급',
          preferredDiscipline: '보드 🏂',
          provider: uid.startsWith('apple') ? SocialAuthProvider.apple : SocialAuthProvider.kakao,
        );
        participantsList.add(prof);
      }
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups_rounded, color: Color(0xFF2563EB), size: 24),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '4인 슬로프 파티 매칭 완료!',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: -0.3),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '대화방 입장 전 함께할 라이더를 확인하세요',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 스키장 파티 안내 배너
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.downhill_skiing_rounded, color: Colors.blue.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '[${post.resortName}] 동일 스키장 실시간 동행 파티',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  '함께할 라이더 프로필',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 8),

                // 4인 라이더 프로필 카드 리스트 (소셜 인증 배지 제거)
                ...participantsList.map((rider) {
                  final isMe = rider.id == currentUser.id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF2563EB).withValues(alpha: 0.05) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isMe ? const Color(0xFF2563EB).withValues(alpha: 0.3) : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: isMe ? const Color(0xFF2563EB) : Colors.indigo.shade400,
                          child: Text(
                            rider.nickname.isNotEmpty ? rider.nickname.characters.first : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      rider.nickname,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: isMe ? const Color(0xFF2563EB) : Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('나', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${rider.homeResort} • ${rider.preferredDiscipline} • ${rider.level}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '프로필 확인 후 [파티 참여하기]를 눌러야 대화방에 연결됩니다.\n[다음에 하기] 선택 시 악용 방지를 위해 5분간 재매칭이 제한됩니다.',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await applyPartySkipCooldown(
                        postIdToLeave: post.id,
                        userId: currentUser.id,
                      );
                      if (!mounted) return;
                      _syncCooldownTimer();
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.orange.shade900,
                          content: const Text('⏱️ 파티 참여를 건너뛰어 5분간 매칭이 제한됩니다. (앱 재실행 시에도 유지)'),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('다음에 하기\n(5분 매칭 제한)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.2)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await clearPendingPartyAcceptance();
                      if (!mounted) return;
                      setState(() {
                        gDailyRandomMatchRemaining = 0;
                      });
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatRoomScreen(post: post),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('파티 참여하기\n(수락)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.2)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _handleMatchTimeout() {
    final targetResort = _selectedResort;
    _cancelMatching(leaveQueue: true);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Row(
            children: [
              Icon(Icons.timer_off_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text('대기 시간 종료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '대기 시간이 초과되어 매칭이 종료되었습니다.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                '15분 동안 [${targetResort.shortName}] 대기 인원(4명)이 모이지 않아 안전하게 대기열에서 퇴장되었습니다.\n\n동일한 스키장으로 바로 다시 매칭을 시작하시겠습니까?',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _selectedResort = targetResort;
                _startMatching();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('재매칭'),
            ),
          ],
        );
      },
    );
  }

  void _cancelMatching({bool leaveQueue = true}) {
    _tickerTimer?.cancel();
    _queueSubscription?.cancel();
    _statusSubscription?.cancel();

    if (leaveQueue && gCurrentUser != null) {
      AppFirebaseService.instance.leaveMatchQueue(_selectedResort.id, gCurrentUser!.id);
    }

    if (mounted) {
      setState(() {
        _isMatching = false;
        _matchedCount = 1;
        _elapsedSeconds = 0;
        _currentQueue.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isMatching) {
      return _buildMatchingQueueView();
    }

    return _buildResortSelectionView();
  }

  // -------------------------------------------------------------
  // 화면 1: 스키장 선택 및 매칭 시작 화면
  // -------------------------------------------------------------
  Widget _buildResortSelectionView() {
    final bool hasTicket = gDailyRandomMatchRemaining > 0;
    final Duration cooldownRemaining = getRemainingSkipCooldown();
    final bool isInCooldown = cooldownRemaining > Duration.zero;
    final int cdSecTotal = cooldownRemaining.inSeconds.clamp(0, 300);
    final String cdMm = (cdSecTotal ~/ 60).toString().padLeft(2, '0');
    final String cdSs = (cdSecTotal % 60).toString().padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 안내 배너
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: Colors.amber, size: 16),
                          SizedBox(width: 4),
                          Text('초고속 4인 파티', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isInCooldown
                            ? Colors.orange.shade700
                            : (hasTicket ? Colors.green.shade600 : Colors.red.shade600),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isInCooldown
                            ? '페널티 $cdMm:$cdSs ⏱️'
                            : (hasTicket ? '1일 1회 가능 🟢' : '오늘 기회 소진 🔴'),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '같은 스키장 라이더들과\n프로필 확인 후 안전한 동행 파티!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '상대방 프로필을 확인하고 직접 수락해야 대화방이 열리는 안전한 동행 시스템입니다.',
                  style: TextStyle(fontSize: 12.5, color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 상단 매칭 시작 버튼 영역 (스키장 선택 바로 위로 이동)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Image.asset(
                        _selectedResort.logoAsset,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(_selectedResort.icon, color: _selectedResort.themeColor, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _selectedResort.shortName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _selectedResort.region,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isInCooldown
                                ? '⏱️ 매칭 제한 페널티 적용 중 ($cdMm:$cdSs 남음)'
                                : (hasTicket ? '⚡️ 오늘 남은 매칭 기회: 1회' : '🔒 오늘 매칭 기회를 모두 사용했습니다'),
                            style: TextStyle(
                              fontSize: 12,
                              color: isInCooldown
                                  ? Colors.orange.shade800
                                  : (hasTicket ? Colors.blue.shade700 : Colors.red.shade600),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _startMatching,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (hasTicket && !isInCooldown) ? const Color(0xFF2563EB) : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: const Color(0xFF2563EB).withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isInCooldown ? Icons.hourglass_bottom_rounded : Icons.groups_rounded, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            isInCooldown
                                ? '매칭 제한 중 ($cdMm:$cdSs 후 재시도 가능)'
                                : (hasTicket
                                    ? '[${_selectedResort.shortName}] 4인 슬로프 파티 찾기 (1/1회)'
                                    : '오늘의 1회 파티 매칭 완료됨 (내일 자정 초기화)'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 스키장 변경/선택 타이틀
          Row(
            children: [
              const Text(
                '스키장 변경',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(width: 8),
              Text(
                '다른 스키장으로 매칭하려면 터치하세요',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 스키장 선택 그리드 (12개 스키장 공식 로고 카드)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: kSkiResorts.length,
            itemBuilder: (context, index) {
              final resort = kSkiResorts[index];
              final isSelected = _selectedResort.id == resort.id;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedResort = resort;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2563EB).withValues(alpha: 0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade200,
                      width: isSelected ? 2.2 : 1.2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            width: 60,
                            height: 40,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade100),
                            ),
                            child: Image.asset(
                              resort.logoAsset,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Icon(resort.icon, color: resort.themeColor, size: 24),
                            ),
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 12, color: Colors.white),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        resort.shortName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? const Color(0xFF2563EB) : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        resort.region.split(' ').last,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 화면 2: 4인 실시간 대기 큐 화면
  // -------------------------------------------------------------
  Widget _buildMatchingQueueView() {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          // 상단 상태 배지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_selectedResort.shortName} 대기열 탐색 중 ($minutes:$seconds)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 레이더 펄스 애니메이션
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                    blurRadius: 24,
                    spreadRadius: 6,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Image.asset(
                  _selectedResort.logoAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(_selectedResort.icon, size: 50, color: const Color(0xFF2563EB)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 매칭 인원 카운트
          Text(
            '$_matchedCount / 4명 모임',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            _matchedCount == 4
                ? '🎉 4인 파티 매칭 완료! 프로필 확인 창이 열립니다...'
                : '실시간 접속 중인 ${_selectedResort.shortName} 슬로프 메이트를 찾는 중...',
            style: TextStyle(
              fontSize: 14,
              color: _matchedCount == 4 ? Colors.green.shade700 : Colors.grey.shade600,
              fontWeight: _matchedCount == 4 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 28),

          // 4인 슬롯 카드 그리드 (군더더기 없는 깔끔한 카드)
          Column(
            children: List.generate(4, (index) {
              final name = index < _currentQueue.length ? _currentQueue[index] : null;
              final isFilled = name != null;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isFilled ? Colors.white : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isFilled ? const Color(0xFF2563EB).withValues(alpha: 0.4) : Colors.grey.shade200,
                    width: isFilled ? 1.5 : 1,
                  ),
                  boxShadow: isFilled
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isFilled ? const Color(0xFF2563EB) : Colors.grey.shade300,
                      child: Icon(
                        isFilled ? Icons.person_rounded : Icons.hourglass_empty_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        isFilled ? name : '대기열 탐색 중...',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isFilled ? Colors.black87 : Colors.grey.shade400,
                        ),
                      ),
                    ),
                    if (isFilled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '참여완료',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                        ),
                      )
                    else
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // 매칭 취소 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _cancelMatching,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('매칭 취소하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 소묶음 3: 같이 탔어요 (후기 & 실시간 설질/사진 피드)
// -------------------------------------------------------------
class RideReviewListView extends StatefulWidget {
  const RideReviewListView({super.key});

  @override
  State<RideReviewListView> createState() => _RideReviewListViewState();
}

class _RideReviewListViewState extends State<RideReviewListView> {
  String _selectedResort = '전체';

  void _showBlockUserDialog(String nickname, {String? targetUid}) {
    final blockTarget = (targetUid != null && targetUid.isNotEmpty) ? targetUid : nickname;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('사용자 차단', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('\'$nickname\' 님을 차단하시겠습니까?\n\n차단 시 해당 사용자가 작성한 모든 모집글과 후기가 더 이상 노출되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (gCurrentUser != null) {
                  gCurrentUser!.blockUser(blockTarget);
                  AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  content: Text('\'$nickname\' 님을 차단했습니다.'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('차단하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unblockedReviews = gRideReviews.where((r) {
      if (r.shouldHide) return false;
      // 내 리뷰는 항상 표시
      if (r.isAuthor || (gCurrentUser != null && r.authorUid == gCurrentUser!.id)) return true;
      if (r.authorUid != null && r.authorUid!.isNotEmpty &&
          (gCurrentUser?.isUserBlocked(r.authorUid!, uid: r.authorUid) ?? false)) {
        return false;
      }
      if (gCurrentUser?.isUserBlocked(r.authorName) ?? false) return false;
      return true;
    }).toList();
    final filteredReviews = _selectedResort == '전체'
        ? unblockedReviews
        : unblockedReviews.where((r) => r.resortName.contains(_selectedResort)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // 상단 스키장 필터 칩
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildFilterChip('전체'),
                  ...kSkiResorts.map((r) => _buildFilterChip(r.shortName)),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // 후기 피드 리스트
          Expanded(
            child: filteredReviews.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.photo_camera_back_outlined, size: 52, color: Color(0xFF2563EB)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '[$_selectedResort] 등록된 후기가 없습니다',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '오늘의 생생한 슬로프 현장 사진과\n설질 후기를 첫 번째로 공유해보세요! (+100P 지급)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (!ensureUserLoggedIn(context, actionName: '설질 & 라이딩 후기를 작성')) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const WriteRideReviewScreen()),
                              ).then((_) {
                                if (mounted) setState(() {});
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                            label: const Text('첫 설질 후기 & 사진 등록하기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    itemCount: filteredReviews.length,
                    itemBuilder: (context, index) {
                      final review = filteredReviews[index];
                      return _buildReviewCard(review);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (!ensureUserLoggedIn(context, actionName: '설질 & 라이딩 후기를 작성')) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WriteRideReviewScreen()),
          ).then((_) {
            if (mounted) setState(() {});
          });
        },
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
        label: const Text('후기 & 사진 남기기', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFilterChip(String name) {
    final isSelected = _selectedResort == name;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedResort = name;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewCard(RideReview review) {
    final timeStr = DateTime.now().difference(review.createdAt).inHours < 1
        ? '${DateTime.now().difference(review.createdAt).inMinutes}분 전'
        : (DateTime.now().difference(review.createdAt).inHours < 24
            ? '${DateTime.now().difference(review.createdAt).inHours}시간 전'
            : '${review.createdAt.month}월 ${review.createdAt.day}일');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200, width: 1.2),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 작성자 & 스키장 헤더
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Image.asset(
                      (review.tags.any((t) => t.contains('보드')) || review.content.contains('보드'))
                          ? 'assets/logos/penguin_board.png'
                          : 'assets/logos/penguin_ski.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              review.authorName,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              review.resortName.split(' ')[0],
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'hide',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_off_outlined, size: 16, color: Colors.black87),
                          SizedBox(width: 8),
                          Text('이 후기 피드에서 즉시 숨기기', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.flag_outlined, size: 16, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('후기 신고하기 (24h 검토)', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('작성자 차단하기', style: TextStyle(fontSize: 13, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'hide') {
                      setState(() {
                        hideContentPermanently(review.id);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF1E3A8A),
                          content: Text('후기가 회원님의 피드에서 즉시 숨김(삭제) 처리되었습니다.'),
                        ),
                      );
                    } else if (val == 'block') {
                      _showBlockUserDialog(review.authorName, targetUid: review.authorUid);
                    } else if (val == 'report') {
                      final currentUserId = gCurrentUser?.id ?? 'me';
                      if (review.reportedUserIds.contains(currentUserId)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('이미 신고가 접수된 후기입니다.')),
                        );
                        return;
                      }

                      showReportContentDialog(
                        context: context,
                        targetType: '후기',
                        targetAuthor: review.authorName,
                        currentReportCount: review.reportCount,
                        onReportSuccess: (reason) {
                          setState(() {
                            hideContentPermanently(review.id);
                            review.reportCount += 1;
                            review.reportedUserIds.add(currentUserId);
                            if (review.reportCount >= 3) {
                              review.isBlinded = true;
                            }
                          });

                          // 🚨 Firestore 실시간 신고 및 3회 자동 블라인드 저장
                          if (review.id.isNotEmpty) {
                            AppFirebaseService.instance.reportReview(review.id, currentUserId);
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF1E3A8A),
                              content: Text('🚨 신고가 접수되어 피드에서 즉시 숨김 처리되었습니다. (24시간 이내 관리자 검토 후 영구 조치)'),
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 후기 본문 텍스트
            Text(
              review.content,
              style: const TextStyle(fontSize: 14.5, color: Colors.black87, height: 1.45),
            ),
            const SizedBox(height: 12),

            // 4. 첨부된 슬로프 사진 갤러리 (실제 Storage 사진 & 프리셋 지원)
            if (review.photoLabels.isNotEmpty) ...[
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.photoLabels.length,
                  itemBuilder: (context, photoIdx) {
                    final photoLabel = review.photoLabels[photoIdx];
                    final isNetworkImage = photoLabel.startsWith('http');

                    if (isNetworkImage) {
                      return GestureDetector(
                        onTap: () {
                          // 사진 크게 보기 다이얼로그
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(12),
                              child: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(
                                      photoLabel,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const CircleAvatar(
                                      backgroundColor: Colors.black54,
                                      child: Icon(Icons.close, color: Colors.white),
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: 200,
                          margin: const EdgeInsets.only(right: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  photoLabel,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return Container(
                                      color: Colors.grey.shade200,
                                      child: const Center(
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: Colors.grey.shade300,
                                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.verified, color: Colors.amber, size: 12),
                                        SizedBox(width: 4),
                                        Text('현장 인증', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return Container(
                      width: 200,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1E3A8A),
                            const Color(0xFF2563EB).withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.camera_alt_rounded, color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text('슬로프 사진', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Center(
                            child: Icon(Icons.snowboarding_rounded, color: Colors.white.withValues(alpha: 0.8), size: 40),
                          ),
                          Text(
                            photoLabel,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 5. 태그 목록
            if (review.tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: review.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            const Divider(height: 1),
            const SizedBox(height: 8),

            // 6. 하단 인터랙션 (좋아요 & 댓글)
            Row(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      review.isLiked = !review.isLiked;
                      review.likeCount += review.isLiked ? 1 : -1;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          review.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 18,
                          color: review.isLiked ? Colors.red : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${review.likeCount}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: review.isLiked ? Colors.red : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '100% 실명 비공개',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 같이 탔어요: 후기 & 사진 작성 화면
// -------------------------------------------------------------
class WriteRideReviewScreen extends StatefulWidget {
  const WriteRideReviewScreen({super.key});

  @override
  State<WriteRideReviewScreen> createState() => _WriteRideReviewScreenState();
}

class _WriteRideReviewScreenState extends State<WriteRideReviewScreen> {
  SkiResort _selectedResort = kSkiResorts.first;
  final TextEditingController _contentController = TextEditingController();
  final List<String> _attachedPhotos = [];
  final List<XFile> _selectedFiles = [];
  final List<String> _selectedTags = [];
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;


  final List<String> _presetTags = [
    '#4인파티매칭후기',
    '#설질대박',
    '#야간라이딩',
    '#초보환영',
    '#인생샷',
    '#안전라이딩',
    '#땡보딩',
  ];

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(imageQuality: 80);
      if (images.isNotEmpty) {
        setState(() {
          _selectedFiles.addAll(images);
        });
      }
    } catch (e) {
      debugPrint('Gallery pick error: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (photo != null) {
        setState(() {
          _selectedFiles.add(photo);
        });
      }
    } catch (e) {
      debugPrint('Camera pick error: $e');
    }
  }

  void _addPhotoDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('슬로프 사진 추가 방식 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('오늘 촬영한 슬로프 현장 사진을 업로드해 보세요.', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
              const SizedBox(height: 16),

              // 1. 갤러리에서 선택
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF2563EB)),
                ),
                title: const Text('앨범/갤러리에서 사진 선택', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                subtitle: const Text('여러 장의 고화질 현장 사진을 첨부할 수 있습니다.', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),

              // 2. 카메라로 촬영
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.amber),
                ),
                title: const Text('카메라로 바로 촬영하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                subtitle: const Text('슬로프에서 지금 바로 촬영하여 등록합니다.', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitReview() async {
    if (!ensureUserLoggedIn(context, actionName: '설질 후기를 등록')) return;

    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('후기 내용을 입력해 주세요.')),
      );
      return;
    }

    // 🛡️ 금칙어 & 외부 링크 실시간 필터링
    final filterError = ContentFilterService.validate(content);
    if (filterError != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('등록 제한 안내', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5)),
            ],
          ),
          content: Text(filterError, style: const TextStyle(fontSize: 13.5, height: 1.45)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    // 📸 1. Firebase Storage에 선택된 실제 이미지들 업로드
    final List<String> finalPhotoUrls = List.from(_attachedPhotos);
    for (final file in _selectedFiles) {
      try {
        final bytes = await file.readAsBytes();
        final url = await AppFirebaseService.instance.uploadReviewImageBytes(bytes, file.name);
        if (url != null) {
          finalPhotoUrls.insert(0, url);
        }
      } catch (e) {
        debugPrint('Image upload error: $e');
      }
    }

    final newReview = RideReview(
      id: '',
      authorName: gCurrentUser?.nickname ?? '익명의 라이더',
      resortName: _selectedResort.name,
      snowCondition: '',
      rating: 5,
      content: content,
      photoLabels: finalPhotoUrls,
      tags: List.from(_selectedTags),
      createdAt: DateTime.now(),
      likeCount: 1,
      isLiked: true,
      commentCount: 0,
    );

    // 🚀 Firestore 클라우드에 실시간 후기 저장
    AppFirebaseService.instance.createReview(newReview);
    gRideReviews.insert(0, newReview);

    if (mounted) {
      setState(() {
        _isUploading = false;
      });
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E3A8A),
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('후기와 사진이 클라우드에 성공적으로 등록되었습니다! 🎿 (+100P 지급)'),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('후기 & 사진 작성', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🛡️ Apple Guideline 1.2: 안전 수칙 및 무관용(Zero-Tolerance) 원칙 고지 카드
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_rounded, color: Color(0xFFDC2626), size: 18),
                      SizedBox(width: 6),
                      Text(
                        '커뮤니티 안전 정책 및 무관용(Zero-Tolerance) 원칙',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '• 본 서비스는 만 19세(18+) 이상 성인 라이더 전용 커뮤니티입니다.\n'
                    '• 부적절한 후기 및 음란/선정적 사진 등록 시 사전 경고 없이 즉각 삭제 처리됩니다.\n'
                    '• 악성 이용자는 무관용 원칙에 따라 24시간 이내 영구 퇴출(계정 이용 정지) 조치됩니다.\n'
                    '• 후기 등록 시 서비스 이용약관(EULA)에 동의한 것으로 간주됩니다.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF7F1D1D), height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => showAppTermsDialog(context),
                    child: const Text(
                      '📜 서비스 이용약관(EULA) 전문 확인하기 >',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
            // 1. 스키장 선택
            const Text('다녀온 스키장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200, width: 1.2),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SkiResort>(
                  value: _selectedResort,
                  isExpanded: true,
                  items: kSkiResorts.map((resort) {
                    return DropdownMenuItem(
                      value: resort,
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 22,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Image.asset(resort.logoAsset, fit: BoxFit.contain),
                          ),
                          const SizedBox(width: 10),
                          Text(resort.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedResort = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. 슬로프 사진 첨부
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('슬로프 사진 첨부', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _addPhotoDialog,
                  icon: const Icon(Icons.add_a_photo_rounded, size: 16, color: Color(0xFF2563EB)),
                  label: const Text('사진 추가', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                ),
              ],
            ),
            // 선택된 실제 사진 썸네일 리스트
            if (_selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _selectedFiles[index];
                    return FutureBuilder<Uint8List>(
                      future: file.readAsBytes(),
                      builder: (context, snapshot) {
                        return Container(
                          width: 90,
                          height: 90,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: snapshot.hasData
                                    ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                                    : Container(color: Colors.grey.shade200, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedFiles.removeAt(index);
                                    });
                                  },
                                  child: const CircleAvatar(
                                    radius: 11,
                                    backgroundColor: Colors.black87,
                                    child: Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
            if (_attachedPhotos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _attachedPhotos.map((photo) {
                  return Chip(
                    avatar: const Icon(Icons.image, size: 16, color: Color(0xFF2563EB)),
                    label: Text(photo, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () {
                      setState(() {
                        _attachedPhotos.remove(photo);
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 20),

            // 5. 후기 내용 작성
            const Text('후기 & 슬로프 꿀팁 공유', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '오늘의 슬로프 설질, 4인 매칭 메이트와의 즐거웠던 기억, 리프트 대기 상황 등을 자유롭게 공유해 주세요!',
                hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 6. 태그 선택
            const Text('추천 태그 선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetTags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag),
                  selected: isSelected,
                  selectedColor: Colors.blue.shade100,
                  checkmarkColor: const Color(0xFF2563EB),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isSelected ? const Color(0xFF1E3A8A) : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(tag);
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 30),

            // 등록 버튼
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                child: _isUploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('사진 클라우드 업로드 중...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      )
                    : const Text('후기 & 사진 등록 완료 🏂', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 탭 3: 스키장 정보 (3열 그리드 + 실시간 날씨 API + 실시간 웹캠)
// -------------------------------------------------------------
class ResortInfoScreen extends StatefulWidget {
  const ResortInfoScreen({super.key});

  @override
  State<ResortInfoScreen> createState() => _ResortInfoScreenState();
}

class _ResortInfoScreenState extends State<ResortInfoScreen> {
  // 스키장별 실시간 날씨 캐시
  final Map<String, ResortWeather> _weathers = {};

  @override
  void initState() {
    super.initState();
    _loadAllWeathers();
  }

  void _loadAllWeathers() async {
    for (final resort in kSkiResorts) {
      final w = await WeatherService.fetchWeather(resort);
      if (w != null && mounted) {
        setState(() {
          _weathers[resort.id] = w;
        });
      }
    }
  }

  Future<void> _launchOfficialWebcamUrl(BuildContext context, SkiResort resort) async {
    final uri = Uri.parse(resort.officialWebcamUrl);
    try {
      // 1순위: 앱 내 사파리 뷰어(SFSafariViewController)로 앱 이탈 없이 쾌적하게 띄움 (시뮬레이터 & 실기기 완벽 지원)
      bool launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched) {
        // 2순위 fallback: 외부 사파리 브라우저 앱으로 열기
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${resort.name} 웹캠 페이지를 열 수 없습니다.')),
        );
      }
    } catch (e) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e2) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('웹캠 연결 실패: $e2')),
          );
        }
      }
    }
  }

  void _showFullScreenTrailMapImage(BuildContext context, SkiResort resort) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: resort.themeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.map_rounded, color: resort.themeColor, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${resort.name} 슬로프 맵',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '💡 두 손가락으로 핀치 줌(확대/축소) 및 드래그 이동이 가능합니다.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 480,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5.0,
                      child: Image.asset(
                        resort.trailMapAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showResortDetailModal(BuildContext context, SkiResort resort) {
    final weather = _weathers[resort.id];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 상단 헤더
                  Row(
                    children: [
                      Container(
                        width: 72,
                        height: 50,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: resort.themeColor.withValues(alpha: 0.25), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: resort.themeColor.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          resort.logoAsset,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(resort.icon, color: resort.themeColor, size: 30),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resort.name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              resort.region,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 1. 실시간 날씨 카드 (Open-Meteo 실시간 API 연동)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          resort.themeColor.withValues(alpha: 0.15),
                          resort.themeColor.withValues(alpha: 0.04),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: resort.themeColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('🌤️ 실시간 날씨 & 설질 환경', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('실시간 API', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (weather == null)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                '날씨 정보를 불러올 수 없습니다',
                                style: TextStyle(fontSize: 12.5, color: Colors.grey, fontWeight: FontWeight.w500),
                              ),
                            ),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text(weather.iconEmoji, style: const TextStyle(fontSize: 28)),
                                  const SizedBox(height: 2),
                                  Text(weather.weatherDesc, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${weather.temp > 0 ? '+' : ''}${weather.temp}°C', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                  Text('체감 ${weather.apparentTemp}°C', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                ],
                              ),
                              Container(height: 36, width: 1, color: Colors.grey.shade300),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('💨 풍속 ${weather.windSpeed}m/s', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text('💧 습도 ${weather.humidity}%', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 1.5 향후 3~5일간 주간 날씨 & 눈(강설량) 예보 (숙박/원정 플래너)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('📅 향후 5일간 날씨 & 강설 예보 ❄️', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('숙박/원정 참고', style: TextStyle(fontSize: 10.5, color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (weather != null && weather.dailyForecasts.isNotEmpty)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: weather.dailyForecasts.map((f) {
                                final isSnow = f.snowfall > 0;
                                return Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: isSnow ? Colors.blue.shade50 : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSnow ? Colors.blue.shade300 : Colors.grey.shade200,
                                      width: isSnow ? 1.2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(f.dayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text(f.iconEmoji, style: const TextStyle(fontSize: 22)),
                                      const SizedBox(height: 4),
                                      Text('${f.maxTemp.round()}° / ${f.minTemp.round()}°', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      if (isSnow) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '❄️ ${f.snowfall}cm',
                                            style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 4),
                                        Text(f.weatherDesc, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          )
                        else
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                '주간 예보 정보를 불러올 수 없습니다',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1.8 실시간 라이더 설질 한줄평 (1일 1회 50P 적립 & 실시간 라이브)
                  ResortLiveSnowReviewSection(resort: resort),
                  const SizedBox(height: 20),

                  // 2. 스키장 슬로프 맵 (코스 안내도)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('🗺️ 슬로프 맵 (코스 안내도)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: () => _showFullScreenTrailMapImage(context, resort),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fullscreen_rounded, size: 14, color: Color(0xFF2563EB)),
                              SizedBox(width: 3),
                              Text('크게보기', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showFullScreenTrailMapImage(context, resort),
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              resort.trailMapAsset,
                              fit: BoxFit.contain,
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.touch_app_rounded, color: Colors.white70, size: 11),
                                    SizedBox(width: 3),
                                    Text('터치하여 전체화면 확대 (핀치줌)', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. 실시간 슬로프 웹캠 (리조트 공식 라이브캠)
                  Row(
                    children: [
                      const Text('📹 실시간 슬로프 웹캠 (공식 라이브캠)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record, color: Colors.red, size: 8),
                            SizedBox(width: 4),
                            Text('OFFICIAL LIVE', style: TextStyle(color: Colors.red, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: resort.themeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.videocam_rounded, color: resort.themeColor, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${resort.shortName} 공식 실시간 웹캠',
                                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '리조트 공식 실시간 슬로프 현장 영상을 확인합니다.',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: resort.themeColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _launchOfficialWebcamUrl(context, resort),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: Text(
                              '${resort.shortName} 공식 웹캠 바로가기',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. 26/27 시즌 운영 시간대
                  const Text('⏰ 26/27 시즌 운영 시간대', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: resort.availableTimeSlots.map((slot) {
                      return Chip(
                        label: Text(slot, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.grey.shade100,
                        side: BorderSide(color: Colors.grey.shade300),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 4. 슬로프 코스 제원 & 난이도 안내
                  DetailedSlopeStatusWidget(resort: resort),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.landscape_rounded,
                color: Color(0xFF2563EB),
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '스키장 정보',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: -0.5,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '날씨 정보 새로고침',
            onPressed: () {
              _loadAllWeathers();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('전체 스키장 실시간 날씨를 갱신했습니다.')),
              );
            },
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        itemCount: kSkiResorts.length,
        itemBuilder: (context, index) {
          final resort = kSkiResorts[index];
          final weather = _weathers[resort.id];
          return _buildResortGridCard(context, resort, weather);
        },
      ),
    );
  }

  Widget _buildResortGridCard(BuildContext context, SkiResort resort, ResortWeather? weather) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1.2),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showResortDetailModal(context, resort),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 실시간 날씨 미니 배지
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  weather != null
                      ? '${weather.iconEmoji} ${weather.temp > 0 ? '+' : ''}${weather.temp.toStringAsFixed(1)}°'
                      : '❄️ 실시간',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),

              // 리조트 공식 로고 이미지
              Container(
                width: 74,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Image.asset(
                  resort.logoAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(resort.icon, color: resort.themeColor, size: 28),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 스키장 이름
              Text(
                resort.shortName,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),

              // 지역
              Text(
                resort.region,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // CCTV & 슬로프 배지
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.videocam, size: 10, color: Colors.red),
                        SizedBox(width: 1),
                        Text('CCTV', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: resort.themeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${resort.slopes.length}개',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: resort.themeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// -------------------------------------------------------------
// ❄️ 스키장 상세 전용 실시간 라이더 설질 한줄평 위젯
// -------------------------------------------------------------
class ResortLiveSnowReviewSection extends StatefulWidget {
  final SkiResort resort;
  const ResortLiveSnowReviewSection({super.key, required this.resort});

  @override
  State<ResortLiveSnowReviewSection> createState() => _ResortLiveSnowReviewSectionState();
}

class _ResortLiveSnowReviewSectionState extends State<ResortLiveSnowReviewSection> {
  final TextEditingController _commentController = TextEditingController();
  String _selectedCondition = '파우더/건설';
  String _selectedEmoji = '❄️';
  bool _isSubmitting = false;

  final List<Map<String, String>> _conditions = const [
    {'label': '파우더/건설', 'emoji': '❄️'},
    {'label': '양호/양설', 'emoji': '✨'},
    {'label': '빙판/아이스', 'emoji': '🧊'},
    {'label': '감자/강설', 'emoji': '🥔'},
    {'label': '슬러시/봄눈', 'emoji': '☀️'},
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    if (!ensureUserLoggedIn(context, actionName: '설질 한줄평을 등록')) return;

    if (!AppFirebaseService.isSnowCommentWritable()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF1E293B),
          content: Row(
            children: [
              Icon(Icons.schedule_rounded, color: Colors.amberAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('새벽 슬로프 정비 시간(03:00~08:00)에는 설질 한줄평을 작성할 수 없습니다. 오전 08:00 이후에 이용해주세요! ❄️'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final text = _commentController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설질 한줄평 내용을 입력해주세요.')),
      );
      return;
    }

    // 🛡️ 실시간 비속어/유해 콘텐츠 자동 필터링 (Apple Guideline 1.2)
    final filterError = ContentFilterService.validate(text);
    if (filterError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade800, content: Text('⚠️ $filterError')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final newComment = LiveSnowComment(
        id: '',
        resortId: widget.resort.id,
        resortName: widget.resort.name,
        authorName: gCurrentUser?.nickname ?? '익명의 라이더',
        authorUid: gCurrentUser?.id,
        content: text,
        snowCondition: _selectedCondition,
        snowConditionEmoji: _selectedEmoji,
        createdAt: DateTime.now(),
      );

      final awarded = await AppFirebaseService.instance.addLiveSnowComment(newComment);
      _commentController.clear();

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      if (awarded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E3A8A),
            content: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('🎉 [${widget.resort.shortName}] 설질 한줄평이 등록되고 50P가 적립되었습니다!'),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('✅ [${widget.resort.shortName}] 설질 한줄평이 등록되었습니다. (오늘 설질 포인트는 이미 적립되었습니다)'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('한줄평 등록 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showBlockUserDialog(String nickname, {String? targetUid}) {
    final blockTarget = (targetUid != null && targetUid.isNotEmpty) ? targetUid : nickname;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('사용자 차단', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('\'$nickname\' 님을 차단하시겠습니까?\n\n차단 시 해당 사용자가 작성한 모든 글과 후기가 목록에서 즉시 숨김 처리됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (gCurrentUser != null) {
                  gCurrentUser!.blockUser(blockTarget);
                  AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  content: Text('\'$nickname\' 님을 차단했습니다. 목록에서 즉시 숨김 처리되었습니다.'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('차단하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveSnowComment>>(
      stream: AppFirebaseService.instance.streamLiveSnowComments(resortId: widget.resort.id),
      builder: (context, snapshot) {
        final rawComments = snapshot.data ?? [];
        final comments = rawComments.where((c) {
          if (c.shouldHide) return false;
          if (gCurrentUser != null && gCurrentUser!.isUserBlocked(c.authorUid ?? c.authorName)) return false;
          return true;
        }).toList();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDD6FE).withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.downhill_skiing_rounded,
                      color: Color(0xFF7C3AED),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '❄️ 실시간 라이더 설질 한줄평',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Text(
                                'LIVE (${comments.length})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '매일 갱신되는 오늘 라이더들의 생생한 슬로프 평가',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 작성 영역 박스
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '내 설질 평가 작성',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Text(
                            '⭐️ +50P 적립',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (!AppFirebaseService.isSnowCommentWritable()) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF64748B)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '새벽 슬로프 정비 시간(03:00~08:00)에는 작성이 잠시 중단됩니다. 오전 08:00에 새롭게 오픈됩니다! ❄️',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // 태그 칩 선택
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _conditions.map((item) {
                          final isSel = _selectedCondition == item['label'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedCondition = item['label']!;
                                  _selectedEmoji = item['emoji']!;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFF2563EB) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSel ? const Color(0xFF2563EB) : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  '${item['emoji']} ${item['label']}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                    color: isSel ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 🛡️ Apple Guideline 1.2: 무관용 원칙 EULA 고지 배너
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, size: 14, color: Color(0xFFDC2626)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '욕설, 비방, 허위 설질 작성 시 무관용 원칙(Zero-Tolerance)에 따라 24시간 이내 즉시 삭제 및 계정 이용 정지 조치됩니다.',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF991B1B), height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 한줄평 입력 필드 + 등록 버튼
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: TextField(
                              controller: _commentController,
                              maxLines: 1,
                              decoration: InputDecoration(
                                hintText: '지금 눈 상태는 어떤가요? (예: 얼음 살짝, 엣지 잘 먹음)',
                                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 38,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitComment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    '등록',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              ),
              const SizedBox(height: 12),

              // 목록
              if (comments.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.ac_unit_rounded, size: 28, color: Colors.blue.shade200),
                      const SizedBox(height: 6),
                      Text(
                        '아직 오늘 등록된 ${widget.resort.shortName}의 실시간 설질 한줄평이 없습니다.\n첫 한줄평을 남기고 50P를 획득해보세요! ❄️',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: comments.length,
                  separatorBuilder: (context, idx) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final c = comments[idx];
                    final diff = DateTime.now().difference(c.createdAt);
                    final timeAgo = diff.inMinutes < 1
                        ? '방금 전'
                        : diff.inMinutes < 60
                            ? '${diff.inMinutes}분 전'
                            : diff.inHours < 24
                                ? '${diff.inHours}시간 전'
                                : '${diff.inDays}일 전';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  '${c.snowConditionEmoji} ${c.snowCondition}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                c.authorName,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                timeAgo,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 16, color: Colors.grey),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'hide',
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility_off_outlined, size: 15, color: Colors.black87),
                                        SizedBox(width: 6),
                                        Text('이 한줄평 피드에서 즉시 숨기기', style: TextStyle(fontSize: 12.5)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'report',
                                    child: Row(
                                      children: [
                                        Icon(Icons.flag_outlined, size: 15, color: Colors.orange),
                                        SizedBox(width: 6),
                                        Text('한줄평 신고하기 (24h 검토)', style: TextStyle(fontSize: 12.5)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'block',
                                    child: Row(
                                      children: [
                                        Icon(Icons.block_rounded, size: 15, color: Colors.red),
                                        SizedBox(width: 6),
                                        Text('작성자 차단하기', style: TextStyle(fontSize: 12.5, color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                                onSelected: (action) {
                                  if (action == 'hide') {
                                    setState(() {
                                      hideContentPermanently(c.id);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: Color(0xFF1E3A8A),
                                        content: Text('한줄평이 회원님의 피드에서 즉시 숨김(삭제) 처리되었습니다.'),
                                      ),
                                    );
                                  } else if (action == 'block') {
                                    _showBlockUserDialog(c.authorName, targetUid: c.authorUid);
                                  } else if (action == 'report') {
                                    final currentUserId = gCurrentUser?.id ?? 'me';
                                    showReportContentDialog(
                                      context: context,
                                      targetType: '설질 한줄평',
                                      targetAuthor: c.authorName,
                                      currentReportCount: c.reportCount,
                                      onReportSuccess: (reason) {
                                        setState(() {
                                          hideContentPermanently(c.id);
                                          c.reportedUserIds.add(currentUserId);
                                          c.reportCount += 1;
                                          if (c.reportCount >= 3) {
                                            c.isBlinded = true;
                                          }
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            backgroundColor: Color(0xFF1E3A8A),
                                            content: Text('🚨 신고가 접수되어 피드에서 즉시 숨김 처리되었습니다. (24시간 이내 관리자 검토 후 조치)'),
                                          ),
                                        );
                                      },
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.content,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: InkWell(
                              onTap: () {
                                AppFirebaseService.instance.toggleLikeLiveSnowComment(
                                  c.id,
                                  gCurrentUser?.nickname ?? '',
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.thumb_up_alt_outlined,
                                      size: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${c.likes}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// -------------------------------------------------------------
// 슬로프 제원 & 코스 정보 위젯
// -------------------------------------------------------------
class DetailedSlopeStatusWidget extends StatefulWidget {
  final SkiResort resort;
  const DetailedSlopeStatusWidget({super.key, required this.resort});

  @override
  State<DetailedSlopeStatusWidget> createState() => _DetailedSlopeStatusWidgetState();
}

class _DetailedSlopeStatusWidgetState extends State<DetailedSlopeStatusWidget> {
  String _selectedSection = '전체';

  @override
  Widget build(BuildContext context) {
    final slopes = widget.resort.detailedSlopes;
    final sections = ['전체', ...{for (var s in slopes) s.section}];

    final filteredSlopes = _selectedSection == '전체'
        ? slopes
        : slopes.where((s) => s.section == _selectedSection).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text('⛷️ 슬로프 코스 제원 & 난이도 안내', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('총 ${slopes.length}개', style: TextStyle(fontSize: 13, color: widget.resort.themeColor, fontWeight: FontWeight.bold)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2)),
              ),
              child: const Text('코스 제원 가이드', style: TextStyle(fontSize: 10.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 구역(Section) 선택 필터 칩
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: sections.map((sec) {
              final isSelected = _selectedSection == sec;
              final count = sec == '전체' ? slopes.length : slopes.where((s) => s.section == sec).length;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('$sec ($count)'),
                  selected: isSelected,
                  selectedColor: widget.resort.themeColor,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                  visualDensity: VisualDensity.compact,
                  onSelected: (val) {
                    if (val) setState(() => _selectedSection = sec);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // 깔끔한 슬로프 제원 카드 목록
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredSlopes.length,
          separatorBuilder: (context, idx) => const SizedBox(height: 8),
          itemBuilder: (context, idx) {
            final slope = filteredSlopes[idx];

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 난이도 배지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: slope.difficulty.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: slope.difficulty.color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      slope.difficulty.label,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: slope.difficulty.color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 슬로프 이름 및 상세 제원
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slope.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (slope.length.isNotEmpty) ...[
                              Icon(Icons.straighten_rounded, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(slope.length, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                              Text('  •  ', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                            ],
                            Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 2),
                            Text(slope.section, style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// 탭 4: 개인설정 화면 (OAuth 계정 연동 & 라이딩 성향 & 익명성 보안)
// -------------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _matchNotification = true;
  bool _chatNotification = true;
  bool _eventNotification = true;

  @override
  void initState() {
    super.initState();
    _eventNotification = gCurrentUser?.eventNotification ?? true;
    if (gCurrentUser != null) {
      unawaited(AppFirebaseService.instance.refreshUserProfile(gCurrentUser!.id));
    }
  }

  // -------------------------------------------------------------
  // 닉네임 변경 및 서버 실시간 중복 체크 다이얼로그
  // -------------------------------------------------------------
  void _showEditNicknameDialog() {
    final user = gCurrentUser;
    if (user == null) return;

    final controller = TextEditingController(text: user.nickname);
    bool isDuplicateChecked = false;
    bool isChecking = false;
    bool isAvailable = false;
    String statusMessage = '';
    Color statusColor = Colors.grey;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.badge_outlined, color: Color(0xFF2563EB), size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Text('익명 닉네임 변경', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '슬로프 메이트들에게 표시될 익명 닉네임입니다.\n(해시태그 없이 2~10자 한글/영문/숫자 가능)',
                      style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            maxLength: 10,
                            onChanged: (_) {
                              if (isDuplicateChecked || isAvailable) {
                                setDialogState(() {
                                  isDuplicateChecked = false;
                                  isAvailable = false;
                                  statusMessage = '닉네임이 변경되었습니다. 다시 중복 확인을 눌러주세요.';
                                  statusColor = Colors.amber.shade800;
                                });
                              }
                            },
                            decoration: InputDecoration(
                              hintText: '새로운 닉네임 입력 (2~10자)',
                              counterText: '',
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: const Icon(Icons.person_outline, size: 18, color: Color(0xFF2563EB)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isChecking
                                ? null
                                : () async {
                                    final input = controller.text.trim();
                                    if (input.length < 2) {
                                      setDialogState(() {
                                        isDuplicateChecked = true;
                                        isAvailable = false;
                                        statusMessage = '2글자 이상 입력해주세요.';
                                        statusColor = Colors.red.shade700;
                                      });
                                      return;
                                    }

                                    if (input == user.nickname) {
                                      setDialogState(() {
                                        isDuplicateChecked = true;
                                        isAvailable = true;
                                        statusMessage = '현재 사용 중인 본인의 닉네임입니다.';
                                        statusColor = Colors.green.shade700;
                                      });
                                      return;
                                    }

                                    setDialogState(() {
                                      isChecking = true;
                                      statusMessage = '서버에서 중복 확인 중...';
                                      statusColor = Colors.grey;
                                    });

                                    final available = await AppFirebaseService.instance.isNicknameAvailable(input, excludeUid: user.id);

                                    setDialogState(() {
                                      isChecking = false;
                                      isDuplicateChecked = true;
                                      isAvailable = available;
                                      if (available) {
                                        statusMessage = '사용 가능한 닉네임입니다.';
                                        statusColor = Colors.green.shade700;
                                      } else {
                                        statusMessage = '이미 다른 라이더가 사용 중인 닉네임입니다.';
                                        statusColor = Colors.red.shade700;
                                      }
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isChecking
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('중복 확인', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    if (statusMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        statusMessage,
                        style: TextStyle(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: (isAvailable && !isChecking)
                      ? () async {
                          final newName = controller.text.trim();
                          setState(() {
                            user.nickname = newName;
                          });
                          await AppFirebaseService.instance.saveUserProfile(user);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF1E3A8A),
                                content: Text('익명 닉네임이 "$newName"으로 안전하게 변경되었습니다.'),
                              ),
                            );
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('변경 완료', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------
  // 파우더 포인트 적립 방법 & 이용 안내 바텀시트
  // -------------------------------------------------------------
  void _showPowderPointGuide() {
    final user = gCurrentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(22.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('❄️', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('파우더 포인트 적립 안내', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('현재 보유 포인트: ${user.snowPoints}P', style: const TextStyle(fontSize: 13, color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('❄️ 포인트 적립 방법', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 10),
                _buildPointEarnRow(emoji: '📅', title: '매일 첫 앱 접속 (출석체크)', points: '+10P', desc: '하루 1회 앱 접속 시 자동 적립'),
                _buildPointEarnRow(emoji: '⚡️', title: '4인 슬로프 파티 성공 & 동행', points: '+50P', desc: '초고속 4인 파티 매칭 완료 시 적립'),
                _buildPointEarnRow(emoji: '🏂', title: '같이타요 모집글 동행 성사', points: '+50P', desc: '모집글 작성 또는 참가 완료 시'),
                _buildPointEarnRow(emoji: '👤', title: '홈 스키장/프로필 설정', points: '+100P', desc: '최초 가입 및 라이딩 성향 등록 (1회)'),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 14),
                const Text('🎁 포인트 혜택 및 등급 안내', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 8),
                Text(
                  '• 1,000P 달성 시 [골드 라이더] 칭호 및 한정판 슬로프 배지 해금\n'
                  '• 2,500P 달성 시 [플래티넘 마스터] 최고 등급 승급\n'
                  '• 2,500P 초과 시 시즌 파우더 랭킹 (명예의 전당 Top 100) 실시간 순위 경쟁 진입',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.5),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPointEarnRow({
    required String emoji,
    required String title,
    required String points,
    required String desc,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(points, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  void _showHomeResortPicker() {
    final user = gCurrentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('홈 스키장 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('가장 자주 이용하는 스키장을 선택하세요.', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: kSkiResorts.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final resort = kSkiResorts[index];
                    final isSelected = user.homeResort == resort.shortName || user.homeResort == resort.name;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: Container(
                        width: 36,
                        height: 24,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Image.asset(
                          resort.logoAsset,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(resort.icon, color: resort.themeColor, size: 16),
                        ),
                      ),
                      title: Text(
                        resort.name,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF2563EB) : Colors.black87,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB)) : null,
                      onTap: () {
                        setState(() {
                          user.homeResort = resort.shortName;
                        });
                        AppFirebaseService.instance.saveUserProfile(user);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPrivacyPolicyModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: Color(0xFF2563EB), size: 24),
                      SizedBox(width: 8),
                      Text('100% 익명성 보호 정책', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🔒 개인정보 비공개 철칙', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                        SizedBox(height: 6),
                        Text(
                          '• 카카오, Apple, Google OAuth는 오직 안전한 본인 인증 및 어뷰징 방지 목적으로만 사용됩니다.\n'
                          '• 실명, 전화번호, 이메일은 다른 사용자 및 슬로프 메이트에게 절대 공개되지 않습니다.\n'
                          '• 모든 매칭 및 대화방은 익명 닉네임으로 안전하게 진행됩니다.',
                          style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('안전한 슬로프 만남 가이드', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '1. 슬로프 만남 조율 시 개인 연락처(카톡 ID, 전화번호 등)를 공유하지 마세요.\n'
                    '2. 만남 장소는 사람이 많은 베이스 광장, 시계탑, 리프트 탑승장 등을 이용하세요.\n'
                    '3. 불쾌감을 주는 행위나 비매너 사용자는 즉시 신고/차단해 주세요.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.5),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showInquiryModal() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final emailController = TextEditingController(text: gCurrentUser?.email ?? '');
    String selectedCategory = '일반 문의';
    bool isSubmitting = false;

    final categories = ['일반 문의', '버그 제보', '기능 제안', '불량 유저 신고'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 16,
                left: 20,
                right: 20,
                bottom: bottomInset + 20,
              ),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.support_agent_rounded, color: Color(0xFF2563EB), size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '고객지원 및 문의 / 제보',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '개발자 메일(ridetogetherrr@gmail.com)로 즉시 전송',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.flash_on_rounded, size: 18, color: Color(0xFF16A34A)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '작성 후 전송하시면 개발자에게 즉시 메일이 발송되며, 24시간 이내 검토 및 조치됩니다.',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFF166534), height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '문의 유형',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((cat) {
                        final isSelected = selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFF2563EB),
                          backgroundColor: Colors.grey.shade100,
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
                            ),
                          ),
                          onSelected: (val) {
                            if (val) {
                              setModalState(() => selectedCategory = cat);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '제목',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      maxLength: 50,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '문의 또는 제보 제목',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '상세 내용',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: contentController,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintText: '문의 사항이나 불량 이용자 닉네임, 상황을 자세히 적어주세요.',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '답변받을 이메일 (선택)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: '답변을 원하시면 이메일을 남겨주세요',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        prefixIcon: const Icon(Icons.email_outlined, size: 20, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final title = titleController.text.trim();
                                final content = contentController.text.trim();
                                if (title.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('문의 제목을 입력해 주세요.')),
                                  );
                                  return;
                                }
                                if (content.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('문의 내용을 입력해 주세요.')),
                                  );
                                  return;
                                }

                                setModalState(() => isSubmitting = true);
                                final messenger = ScaffoldMessenger.of(context);

                                try {
                                  final success = await AppFirebaseService.instance.submitInquiry(
                                    category: selectedCategory,
                                    title: title,
                                    content: content,
                                    replyEmail: emailController.text.trim(),
                                  );

                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: success ? const Color(0xFF1E3A8A) : Colors.red.shade700,
                                        content: Text(
                                          success
                                              ? '📨 문의가 개발자에게 전달되었습니다. 신속히 확인하겠습니다!'
                                              : '⚠️ 전송에 실패했습니다. 다시 시도해 주세요.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setModalState(() => isSubmitting = false);
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('전송 중 오류 발생: $e')),
                                    );
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    '문의 / 제보 전송하기',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                        ),
                        onPressed: () async {
                          final title = titleController.text.trim();
                          final content = contentController.text.trim();
                          final subject = Uri.encodeComponent('[같이타요 $selectedCategory] ${title.isEmpty ? "문의사항" : title}');
                          final body = Uri.encodeComponent(
                            '문의 내용:\n${content.isEmpty ? "(내용을 입력하세요)" : content}\n\n'
                            '---\n'
                            '발신자: ${gCurrentUser?.nickname ?? "익명"} (${gCurrentUser?.id ?? "anonymous"})\n'
                            '회신 이메일: ${emailController.text.trim()}',
                          );
                          final uri = Uri.parse('mailto:ridetogetherrr@gmail.com?subject=$subject&body=$body');
                          try {
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            } else {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          } catch (e) {
                            debugPrint('mailto launch error: $e');
                          }
                        },
                        icon: const Icon(Icons.mail_rounded, size: 16),
                        label: const Text(
                          '직접 기본 메일 앱으로 작성하기',
                          style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('정말 로그아웃 하시겠습니까?\n로그아웃 시 소셜 로그인 화면으로 이동합니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await AppFirebaseService.instance.signOut();
                for (final p in gRidePosts) {
                  p.isJoined = false;
                  p.unreadCount = 0;
                }
                gRidePostsNotifier.value = List<RidePost>.from(gRidePosts);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('로그아웃되었습니다.'),
                    backgroundColor: Colors.black87,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('로그아웃'),
            ),
          ],
        );
      },
    );
  }

  /// 🔒 Apple App Store 심사 필수 항목 (가이드라인 5.1.1(v)): 회원탈퇴 및 개인 활동 데이터 영구 파기
  void _deleteAccount() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('회원탈퇴', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '정말 회원탈퇴 하시겠습니까?\n\n'
                '탈퇴 시 모든 계정 정보, 성사된 동행 내역, 작성한 모집글 및 대화 기록, 보유 파우더 포인트가 즉시 영구 삭제되며 복구할 수 없습니다.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security_rounded, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Apple 개인정보 보호 규정에 따라 클라우드 데이터 및 알림 토큰이 즉시 영구 파기됩니다.',
                        style: TextStyle(fontSize: 11.5, color: Colors.red.shade800, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final currentUser = gCurrentUser;
                if (currentUser != null) {
                  await AppFirebaseService.instance.deleteUserAccount(currentUser.id);
                }
                setState(() {
                  gCurrentUser = null;
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('회원탈퇴 및 모든 데이터 파기가 완료되었습니다.'),
                    backgroundColor: Colors.black87,
                  ),
                );
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('탈퇴 및 데이터 파기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile?>(
      valueListenable: gCurrentUserNotifier,
      builder: (context, user, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 1,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.manage_accounts_rounded,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '개인설정 & 활동기록',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: -0.5,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          body: user == null
              ? _buildLoggedOutView()
              : RefreshIndicator(
                  color: const Color(0xFF2563EB),
                  onRefresh: () async {
                    if (gCurrentUser != null) {
                      await AppFirebaseService.instance.refreshUserProfile(gCurrentUser!.id);
                      if (mounted) setState(() {});
                    }
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. 소셜 로그인 계정 프로필 카드
                        _buildProfileCard(user),

                        const SizedBox(height: 24),

                        // 2. 나의 슬로프 활동 지표 대시보드
                        _buildSectionTitle('나의 슬로프 활동 지표 🏆'),
                        const SizedBox(height: 8),
                        _buildActivityDashboardCard(user),

                        const SizedBox(height: 24),

                        // 3. 나의 슬로프 배지 보관함
                        _buildSectionTitle('슬로프 배지 보관함 🎖️'),
                        const SizedBox(height: 8),
                        _buildBadgeCollectionCard(user),

                        const SizedBox(height: 24),

                        // 4. 나의 라이딩 성향 설정
                        _buildSectionTitle('나의 라이딩 설정 🏂'),
                        const SizedBox(height: 8),
                        _buildRidingPreferenceCard(user),

                        const SizedBox(height: 24),

                        // 5. 알림 및 보안 센터
                        _buildSectionTitle('알림 & 익명성 보안 🔒'),
                        const SizedBox(height: 8),
                        _buildSecurityCard(),

                        const SizedBox(height: 24),

                        // 6. 계정 관리
                        _buildSectionTitle('계정 관리'),
                        const SizedBox(height: 8),
                        _buildAccountCard(user),

                        const SizedBox(height: 30),
                        Center(
                          child: Text(
                            '같이타요 v1.0.0 • 26/27 시즌\n카카오 • Apple 공식 OAuth 연동',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // 위젯 2: 나의 슬로프 활동 지표 대시보드 (매너온도/후기수 제거 & 포인트 적립안내 연동)
  // -------------------------------------------------------------
  Widget _buildActivityDashboardCard(UserProfile user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.handshake_rounded,
                  iconColor: const Color(0xFF2563EB),
                  label: '성사된 동행',
                  value: '${user.completedRidesCount}회',
                  subText: '성공적인 만남',
                ),
              ),
              Container(width: 1, height: 48, color: Colors.grey.shade200),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.military_tech_rounded,
                  iconColor: Colors.amber.shade700,
                  label: '라이더 칭호',
                  value: user.effectiveRiderTitle,
                  subText: '상위 15% 라이더',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _showPowderPointGuide,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.ac_unit_rounded, size: 16, color: Color(0xFF6366F1)),
                            const SizedBox(width: 6),
                            Text('파우더 포인트', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('적립방법 >', style: TextStyle(fontSize: 9.5, color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${user.snowPoints}P', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 2),
                        const Text('터치하여 적립 방법 확인', style: TextStyle(fontSize: 10.5, color: Color(0xFF6366F1), fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 48, color: Colors.grey.shade200),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: const Color(0xFF0D9488),
                  label: '획득 배지',
                  value: '${user.badges.where((b) => b.isUnlocked).length}개',
                  subText: '슬로프 퀘스트 완료',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 2),
          Text(subText, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 위젯 3: 나의 슬로프 배지 보관함
  // -------------------------------------------------------------
  Widget _buildBadgeCollectionCard(UserProfile user) {
    final unlockedCount = user.badges.where((b) => b.isUnlocked).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('획득한 슬로프 배지', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$unlockedCount / ${user.badges.length}개 획득',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: user.badges.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              final badge = user.badges[index];
              return GestureDetector(
                onTap: () => _showBadgeDetailDialog(badge),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badge.isUnlocked ? const Color(0xFFF1F5F9) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: badge.isUnlocked ? const Color(0xFF2563EB).withValues(alpha: 0.3) : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        badge.isUnlocked ? badge.emoji : '🔒',
                        style: const TextStyle(fontSize: 26),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        badge.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: badge.isUnlocked ? Colors.black87 : Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        badge.isUnlocked ? badge.unlockedDate : '미획득',
                        style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showBadgeDetailDialog(RiderBadge badge) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: badge.isUnlocked ? Colors.blue.shade50 : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Text(badge.isUnlocked ? badge.emoji : '🔒', style: const TextStyle(fontSize: 44)),
              ),
              const SizedBox(height: 14),
              Text(badge.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                badge.description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 12),
              if (badge.isUnlocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('획득일: ${badge.unlockedDate}', style: TextStyle(fontSize: 11.5, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('아직 획득하지 못한 배지입니다', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoggedOutView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline_rounded, size: 48, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 18),
            const Text(
              '로그인이 필요합니다',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '카카오, Apple, Google 소셜 계정으로\n3초 만에 안전하게 시작해보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ).then((_) {
                    if (mounted) setState(() {});
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('소셜 로그인 시작하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
    );
  }

  Widget _buildProfileCard(UserProfile user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 프로필 아바타 (주종목에 따라 스키/보드 펭귄 자동 반영) + OAuth 뱃지
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Image.asset(
                        user.disciplineAvatarAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: user.providerColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        user.provider == SocialAuthProvider.kakao
                            ? 'K'
                            : (user.provider == SocialAuthProvider.google ? 'G' : ''),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: user.providerTextColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.nickname,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _showEditNicknameDialog,
                          child: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: user.providerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${user.providerDisplayName} (${user.email})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: user.provider == SocialAuthProvider.kakao
                              ? const Color(0xFF854D0E)
                              : (user.provider == SocialAuthProvider.google
                                  ? const Color(0xFF1E3A8A)
                                  : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniInfo('홈 스키장', user.homeResort),
              _buildMiniInfo('주 종목', user.preferredDiscipline),
              _buildMiniInfo('라이딩 레벨', user.level),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildRidingPreferenceCard(UserProfile user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.landscape_rounded, color: Color(0xFF2563EB)),
            title: const Text('홈 스키장 변경', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user.homeResort, style: const TextStyle(fontSize: 13.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            onTap: _showHomeResortPicker,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.downhill_skiing_rounded, color: Color(0xFF2563EB)),
            title: const Text('주 종목', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            trailing: DropdownButton<String>(
              value: user.preferredDiscipline,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF2563EB)),
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: '스노보드', child: Text('스노보드 🏂')),
                DropdownMenuItem(value: '스키', child: Text('스키 🎿')),
                DropdownMenuItem(value: '스키/보드 혼합', child: Text('둘 다 🎿🏂')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    user.preferredDiscipline = val;
                  });
                  AppFirebaseService.instance.saveUserProfile(user);
                }
              },
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.speed_rounded, color: Color(0xFF2563EB)),
            title: const Text('라이딩 레벨', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            trailing: DropdownButton<String>(
              value: user.level,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF2563EB)),
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: '초급', child: Text('초급')),
                DropdownMenuItem(value: '초중급', child: Text('초중급')),
                DropdownMenuItem(value: '중급', child: Text('중급')),
                DropdownMenuItem(value: '상급', child: Text('상급')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    user.level = val;
                  });
                  AppFirebaseService.instance.saveUserProfile(user);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showBlockedUsersModal() {
    final user = gCurrentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.block_rounded, color: Colors.red, size: 22),
                      const SizedBox(width: 8),
                      const Text('차단된 사용자 관리', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${user.blockedUsers.length}명', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('차단된 사용자의 모집글과 후기는 숨김 처리되며, 향후 참가 시 알림이 제공됩니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  if (user.blockedUsers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('현재 차단된 사용자가 없습니다.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: user.blockedUsers.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final name = user.blockedUsers[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            leading: CircleAvatar(
                              backgroundColor: Colors.red.shade50,
                              child: const Icon(Icons.person_off_rounded, color: Colors.red, size: 18),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            trailing: TextButton(
                              onPressed: () {
                                setModalState(() {
                                  user.unblockUser(name);
                                });
                                AppFirebaseService.instance.saveUserProfile(user);
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF1E3A8A),
                                    content: Text('\'$name\' 님의 차단을 해제했습니다.'),
                                  ),
                                );
                              },
                              child: const Text('차단 해제', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSecurityCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.bolt_rounded, color: Colors.amber),
            title: const Text('4인 슬로프 파티 성공 알림', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('매칭 성사 시 푸시 알림 수신', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            value: _matchNotification,
            activeThumbColor: const Color(0xFF2563EB),
            onChanged: (val) => setState(() => _matchNotification = val),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF2563EB)),
            title: const Text('새 채팅 메시지 알림', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('대화방 새 메시지 실시간 알림', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            value: _chatNotification,
            activeThumbColor: const Color(0xFF2563EB),
            onChanged: (val) => setState(() => _chatNotification = val),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFE11D48)),
            title: const Text('시즌 이벤트 및 혜택 알림 (선택)', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('크리스마스/시즌 특별 매칭 및 게릴라 이벤트 푸시 수신', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            value: _eventNotification,
            activeThumbColor: const Color(0xFF2563EB),
            onChanged: (val) async {
              setState(() {
                _eventNotification = val;
                if (gCurrentUser != null) {
                  gCurrentUser!.eventNotification = val;
                  gCurrentUser!.eventConsentDate = DateTime.now();
                }
              });
              await NotificationService.instance.setEventNotificationEnabled(val);
              if (gCurrentUser != null) {
                AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
              }
              final now = DateTime.now();
              final dateStr = '${now.year}년 ${now.month}월 ${now.day}일';
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: val ? const Color(0xFF1E3A8A) : Colors.grey.shade800,
                  content: Text(
                    val
                        ? '이벤트 및 혜택 알림 수신에 동의하셨습니다. ($dateStr)'
                        : '이벤트 및 혜택 알림 수신이 해제되었습니다. ($dateStr)',
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
            title: const Text('차단된 사용자 관리', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: Text('현재 ${gCurrentUser?.blockedUsers.length ?? 0}명의 사용자를 차단 중입니다', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${gCurrentUser?.blockedUsers.length ?? 0}명', style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            onTap: _showBlockedUsersModal,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.shield_outlined, color: Colors.green),
            title: const Text('100% 익명성 보호 정책', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('개인정보 노출 방지 및 보안 가이드', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: _showPrivacyPolicyModal,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(UserProfile user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.sync_rounded, color: Color(0xFF2563EB)),
            title: const Text('다른 소셜 계정으로 변경', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.description_outlined, color: Color(0xFF2563EB)),
            title: const Text('서비스 이용약관 (EULA)', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('무관용 원칙 및 커뮤니티 안전 정책', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: () => showAppTermsDialog(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF2563EB)),
            title: const Text('개인정보 처리방침', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: () => showAppPrivacyDialog(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded, color: Color(0xFF0284C7)),
            title: const Text('고객지원 및 불량 유저 제보', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('제목·내용 작성 후 즉시 개발자 메일 전송 (24시간 조치)', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: _showInquiryModal,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.grey),
            title: const Text('로그아웃', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.black87)),
            onTap: _logout,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.person_remove_rounded, color: Colors.red.shade400),
            title: Text('회원탈퇴 (계정 영구 삭제)', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.red.shade600)),
            subtitle: Text('모든 개인 데이터 및 활동 기록 즉시 파기', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 이용약관(EULA) & 개인정보 처리방침 공용 모달 다이얼로그
// -------------------------------------------------------------
void showAppTermsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.description_outlined, color: Color(0xFF2563EB)),
          SizedBox(width: 8),
          Text('서비스 이용약관 (EULA)', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '부적절한 콘텐츠 및 악성 이용자에 대한 무관용 원칙 (Zero-Tolerance Policy)\n욕설, 음란, 비방, 불법 행위 적발 시 사전 경고 없이 즉각 삭제 및 계정이 영구 정지됩니다.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF991B1B), fontWeight: FontWeight.w600, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '1. 커뮤니티 안전 정책 및 UGC 규정 (Apple 가이드라인 1.2 준수)\n'
                '• 본 서비스는 건전하고 안전한 라이딩 커뮤니티 조성을 위해 부적절한 콘텐츠에 대한 무관용 원칙을 적용합니다.\n'
                '• 음란물, 불법 도박, 타인에 대한 욕설/비하/성희롱, 외부 연락처 유도 등은 일체 금지됩니다.\n\n'
                '2. 실시간 방어 및 제재 시스템\n'
                '• 금칙어 실시간 필터링: 모집글 및 채팅 작성 시 도박/음란 키워드는 즉각 차단됩니다.\n'
                '• 원터치 차단 및 신고: 부적절한 글이나 유저는 원클릭으로 즉시 차단/신고할 수 있으며, 차단 즉시 화면에서 숨김 처리됩니다.\n'
                '• 24시간 내 신속 조치: 접수된 모든 신고는 24시간 이내에 검토하여 콘텐츠 삭제 및 영구 계정 제재 조치가 취해집니다.\n\n'
                '3. 고객지원 및 불량 유저 신고처\n'
                '• 고객지원 이메일: ridetogetherrr@gmail.com\n'
                '• 공식 저장소: https://github.com/tlskals/eatSleepRide',
                style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인 및 동의', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

void showAppPrivacyDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.privacy_tip_outlined, color: Color(0xFF2563EB)),
          SizedBox(width: 8),
          Text('개인정보 처리방침', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
        ],
      ),
      content: const SizedBox(
        width: double.maxFinite,
        height: 380,
        child: SingleChildScrollView(
          child: Text(
            '같이타요(Eat Sleep Ride)는 이용자의 소중한 개인정보를 보호하며, 관련 법령 및 Apple 개인정보 보호 가이드라인을 철저히 준수합니다.\n\n'
            '1. 수집 항목 및 방법\n'
            '• 소셜 인증(카카오, Apple, Google)을 통한 고유 식별자(UID), 이메일, 닉네임만 수집하며 주민번호, 실명, 전화번호는 수집하지 않습니다.\n\n'
            '2. 이용 목적\n'
            '• 회원 식별, 스키장 동행 매칭 및 실시간 단체 채팅 서비스 제공, 푸시 알림 발송.\n\n'
            '3. 인앱 회원탈퇴 및 즉시 영구 파기 (가이드라인 5.1.1(v))\n'
            '• 이용자는 앱 내 [계정 설정] > [회원탈퇴]를 통해 언제든지 즉시 계정 및 모든 활동 데이터를 영구 삭제할 수 있습니다.\n\n'
            '4. 개인정보 보호 책임자 및 문의\n'
            '• 이메일: ridetogetherrr@gmail.com',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
          ),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

// -------------------------------------------------------------
// OAuth 소셜 로그인 화면 (카카오 • Apple • Google 전용)
// -------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _eulaAgreed = true;

  void _handleSocialLogin(BuildContext context, SocialAuthProvider provider) async {
    if (!_eulaAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('서비스 이용약관(EULA) 및 무관용 정책에 동의해주세요.')),
            ],
          ),
        ),
      );
      return;
    }
    UserProfile? profile;
    if (provider == SocialAuthProvider.kakao) {
      profile = await AppFirebaseService.instance.signInWithKakao();
    } else if (provider == SocialAuthProvider.apple) {
      profile = await AppFirebaseService.instance.signInWithApple();
    } else if (provider == SocialAuthProvider.google) {
      profile = await AppFirebaseService.instance.signInWithGoogle();
    }

    if (context.mounted) {
      if (profile != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E3A8A),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('${profile.providerDisplayName} 로그인 완료! 환영합니다 🎿'),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF334155),
            content: Text('로그인이 취소되었거나 인증에 실패했습니다.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(),

              // 로고 & 타이틀
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.downhill_skiing_rounded, color: Colors.white, size: 42),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '같이타요',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '국내 12개 스키장 4인 실시간 슬로프 파티\n& 슬로프 메이트 커뮤니티',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade100,
                  height: 1.45,
                ),
              ),

              const Spacer(),

              // 🛡️ Apple Guideline 1.2: 필수 EULA 및 무관용 정책 명시적 동의 체크박스
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _eulaAgreed ? const Color(0xFF60A5FA).withValues(alpha: 0.4) : Colors.red.shade400,
                  ),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _eulaAgreed,
                      activeColor: const Color(0xFF2563EB),
                      checkColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) {
                        setState(() {
                          _eulaAgreed = val ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _eulaAgreed = !_eulaAgreed;
                          });
                        },
                        child: const Text(
                          '[필수] 이용약관(EULA) 및 무관용(Zero-Tolerance) 원칙 동의',
                          style: TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => showAppTermsDialog(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        '보기',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF93C5FD), decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 1. 카카오 로그인 버튼 (#FEE500)
              _buildSocialButton(
                context: context,
                provider: SocialAuthProvider.kakao,
                title: '카카오로 3초 만에 시작하기',
                bgColor: const Color(0xFFFEE500),
                textColor: const Color(0xFF191919),
                iconWidget: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFF191919),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.chat_bubble_rounded, color: Color(0xFFFEE500), size: 13),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Apple 로그인 버튼 (White)
              _buildSocialButton(
                context: context,
                provider: SocialAuthProvider.apple,
                title: 'Apple로 계속하기',
                bgColor: Colors.white,
                textColor: Colors.black,
                iconWidget: const Icon(Icons.apple_rounded, color: Colors.black, size: 24),
              ),
              const SizedBox(height: 12),

              // 3. Google 로그인 버튼 (White / Modern Dark Theme Contrast)
              _buildSocialButton(
                context: context,
                provider: SocialAuthProvider.google,
                title: 'Google로 시작하기',
                bgColor: Colors.white,
                textColor: const Color(0xFF1F1F1F),
                iconWidget: _buildGoogleLogo(size: 20),
              ),

              const SizedBox(height: 18),

              // EULA & 커뮤니티 안전 정책 및 무관용 원칙 고지
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Column(
                  children: [
                    Text(
                      '로그인 시 이용약관(EULA) 및 개인정보 처리방침에 동의하게 됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade100, height: 1.35),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ 부적절한 콘텐츠 및 악성 이용자는 무관용 원칙(Zero-Tolerance)에 따라 즉시 삭제 및 영구 이용 정지됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.amber.shade200, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => showAppTermsDialog(context),
                          child: const Text(
                            '이용약관(EULA) 보기',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF93C5FD),
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF93C5FD),
                            ),
                          ),
                        ),
                        Text('  •  ', style: TextStyle(color: Colors.blue.shade300, fontSize: 10)),
                        InkWell(
                          onTap: () => showAppPrivacyDialog(context),
                          child: const Text(
                            '개인정보 처리방침 보기',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF93C5FD),
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF93C5FD),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required BuildContext context,
    required SocialAuthProvider provider,
    required String title,
    required Color bgColor,
    required Color textColor,
    required Widget iconWidget,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () => _handleSocialLogin(context, provider),
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleLogo({double size = 20}) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.22;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Red (Top arc)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -3.14159 * 0.75, 3.14159 * 0.5, false, paint);

    // Yellow (Left arc)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 3.14159 * 0.75, 3.14159 * 0.5, false, paint);

    // Green (Bottom arc)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 3.14159 * 0.25, 3.14159 * 0.5, false, paint);

    // Blue (Right arc)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -3.14159 * 0.25, 3.14159 * 0.5, false, paint);

    // Blue horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(size.width - strokeWidth / 2, center.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


// -------------------------------------------------------------
// 게시글 상세 화면
// -------------------------------------------------------------

class RidePostDetailScreen extends StatefulWidget {
  final RidePost post;

  const RidePostDetailScreen({super.key, required this.post});

  @override
  State<RidePostDetailScreen> createState() => _RidePostDetailScreenState();
}

class _RidePostDetailScreenState extends State<RidePostDetailScreen> {
  void _handleBumpPost() {
    final post = widget.post;
    if (!post.isAuthor || post.isExpired) return;

    final now = DateTime.now();
    if (post.bumpedAt != null) {
      final diffInSeconds = now.difference(post.bumpedAt!).inSeconds;
      const intervalSeconds = 5 * 60; // 5분 = 300초
      if (diffInSeconds < intervalSeconds) {
        final remainingSec = intervalSeconds - diffInSeconds;
        final remainingMin = (remainingSec / 60).ceil();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B),
            content: Row(
              children: [
                const Icon(Icons.access_time_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text('게시글 끌어올리기는 5분 간격으로 가능합니다. (약 $remainingMin분 후 가능)'),
              ],
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      post.bumpedAt = now;
    });

    // 전역 리스트 gRidePosts 및 메모리 동기화
    final idx = gRidePosts.indexWhere((p) => (p.id.isNotEmpty && p.id == post.id) || (p.title == post.title && p.authorName == post.authorName));
    if (idx != -1) {
      gRidePosts[idx].bumpedAt = now;
    }

    if (post.id.isNotEmpty) {
      AppFirebaseService.instance.bumpRidePost(post.id, now);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF1E3A8A),
        content: Row(
          children: [
            Icon(Icons.bolt_rounded, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text('⚡ 게시글을 목록 최상단으로 끌어올렸습니다.'),
          ],
        ),
      ),
    );
  }

  void _joinRide() {
    if (!ensureUserLoggedIn(context, actionName: '모임에 참여')) return;

    if (gPostBanUntil != null && DateTime.now().isBefore(gPostBanUntil!)) {
      final remainingMin = gPostBanUntil!.difference(DateTime.now()).inMinutes;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text('🚨 슬로프 파티 중도 퇴장 페널티로 인해 앞으로 ${remainingMin + 1}분 동안 참가 신청이 제한됩니다.'),
        ),
      );
      return;
    }

    if (widget.post.isFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집 정원이 마감되었습니다.')),
      );
      return;
    }

    // 🔒 차단한 사용자가 참여 중인지 체크 (익명성 유지하며 노티)
    final hasBlockedParticipant = widget.post.participantNames.any(
      (name) => gCurrentUser?.isUserBlocked(name) ?? false,
    );

    if (hasBlockedParticipant) {
      _showBlockedParticipantWarningDialog();
      return;
    }

    _executeJoinRide();
  }

  void _showBlockedParticipantWarningDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
            SizedBox(width: 8),
            Text('차단된 사용자 참여 안내', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          '이 모임의 참가자 중 회원님이 차단하신 사용자가 1명 포함되어 있습니다.\n\n불편한 만남을 방지하기 위해 참여 전 확인을 권장합니다. 그래도 참여하시겠습니까?',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _executeJoinRide();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('그래도 참여하기'),
          ),
        ],
      ),
    );
  }

  void _executeJoinRide() {
    final String myAssignedName;
    if (widget.post.isAnonymous) {
      myAssignedName = widget.post.getNextAnonymousName();
    } else {
      myAssignedName = gCurrentUser?.nickname ?? '익명의 라이더';
    }

    setState(() {
      widget.post.isJoined = true;
      widget.post.currentMembers += 1;
      if (!widget.post.participantNames.contains(myAssignedName)) {
        widget.post.participantNames.add(myAssignedName);
      }
      widget.post.chatMessages.add(
        ChatMessage(
          sender: '시스템',
          text: '새로운 슬로프 메이트($myAssignedName)가 대화방에 참여했습니다! 👋\n만남 장소와 착용 복장을 조율해보세요.',
          time: DateTime.now(),
          isSystem: true,
        ),
      );
    });

    // 🚀 Firestore 실시간 참여 동기화
    if (widget.post.id.isNotEmpty) {
      AppFirebaseService.instance.toggleJoinRidePost(widget.post.id, myAssignedName);
    }

    // 🔔 방장에게 동행 참가 푸시 알림 전송 (상대방 기기만 수신)
    final authorUid = widget.post.authorUid;
    NotificationService.instance.notifyRider(
      senderNickname: myAssignedName,
      targetAuthorName: widget.post.authorName,
      targetParticipants: [widget.post.authorName],
      targetUids: (authorUid != null && authorUid.isNotEmpty) ? [authorUid] : null,
      title: '🎉 [${widget.post.resortName.split(' ')[0]}] 동행 참가 알림',
      body: '\'$myAssignedName\' 님이 \'${widget.post.title}\' 모임에 참가했습니다!',
      type: 'ride_join',
      postId: widget.post.id,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF1E3A8A),
        content: Text('동행 참가 신청이 완료되었습니다! 대화방에 입장해보세요. 🎉'),
      ),
    );
  }


  void _showBlockAuthorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('작성자 차단', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('\'${widget.post.authorName}\' 님을 차단하시겠습니까?\n\n차단 시 해당 작성자의 글이 목록에서 숨김 처리되며, 향후 참가 시 알림이 제공됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (gCurrentUser != null) {
                final target = (widget.post.authorUid != null && widget.post.authorUid!.isNotEmpty)
                    ? widget.post.authorUid!
                    : widget.post.authorName;
                gCurrentUser!.blockUser(target);
                AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
              }
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  content: Text('\'${widget.post.authorName}\' 님을 차단했습니다.'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('차단하기'),
          ),
        ],
      ),
    );
  }

  void _showDeletePostDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('모집글 삭제', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          '작성하신 같이타요 모집글을 삭제하시겠습니까?\n\n삭제 시 목록에서 즉시 제거되며 대화방이 닫힙니다.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (widget.post.id.isNotEmpty) {
                await AppFirebaseService.instance.deleteRidePost(widget.post.id);
              }
              gRidePosts.removeWhere((p) => (p.id.isNotEmpty && p.id == widget.post.id) || (p.title == widget.post.title && p.authorName == widget.post.authorName));
              gRidePostsNotifier.value = List<RidePost>.from(gRidePosts);
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('모집글이 삭제되었습니다.'), backgroundColor: Colors.black87),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final bool canEnterChat = post.canAccessChat;

    return Scaffold(
      appBar: AppBar(
        title: const Text('모집글 상세 정보'),
        actions: [
          if (canEnterChat)
            IconButton(
              icon: const Icon(Icons.mark_chat_unread_rounded, color: Color(0xFF2563EB)),
              tooltip: '대화방 열기',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatRoomScreen(post: post)),
                ).then((_) => setState(() {}));
              },
            ),
          if (post.isAuthor)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onSelected: (val) {
                if (val == 'bump') {
                  _handleBumpPost();
                } else if (val == 'delete') {
                  _showDeletePostDialog();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'bump',
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 18, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('게시글 끌어올리기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('모집글 삭제하기', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onSelected: (val) {
                if (val == 'hide') {
                  setState(() {
                    hideContentPermanently(post.id);
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xFF1E3A8A),
                      content: Text('게시글이 회원님의 피드에서 즉시 숨김(삭제) 처리되었습니다.'),
                    ),
                  );
                } else if (val == 'block') {
                  _showBlockAuthorDialog();
                } else if (val == 'report') {
                  final currentUserId = gCurrentUser?.id ?? 'me';
                  if (post.reportedUserIds.contains(currentUserId)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('이미 신고가 접수된 모집글입니다.')),
                    );
                    return;
                  }

                  showReportContentDialog(
                    context: context,
                    targetType: '모집글',
                    targetAuthor: post.authorName,
                    currentReportCount: post.reportCount,
                    onReportSuccess: (reason) {
                      setState(() {
                        hideContentPermanently(post.id);
                        post.reportCount += 1;
                        post.reportedUserIds.add(currentUserId);
                        if (post.reportCount >= 3) {
                          post.isBlinded = true;
                        }
                      });

                      // 🚨 Firestore 실시간 신고 및 3회 자동 블라인드 저장
                      if (post.id.isNotEmpty) {
                        AppFirebaseService.instance.reportRidePost(post.id, currentUserId);
                      }

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF1E3A8A),
                          content: Text('🚨 신고가 접수되어 피드에서 즉시 숨김 처리되었습니다. (24시간 이내 관리자 검토 후 영구 조치)'),
                        ),
                      );
                    },
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'hide',
                  child: Row(
                    children: [
                      Icon(Icons.visibility_off_outlined, size: 16, color: Colors.black87),
                      SizedBox(width: 8),
                      Text('이 글 피드에서 즉시 숨기기', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag_outlined, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('게시글 신고하기 (24h 검토)', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block_rounded, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('작성자 차단하기', style: TextStyle(fontSize: 13, color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
                  child: const Icon(Icons.person, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        if (post.isAnonymous) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield_rounded, size: 10, color: Color(0xFF2563EB)),
                                SizedBox(width: 2),
                                Text('익명모드', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text('모집현황: ${post.currentMembers}/${post.maxMembers + 1}명', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const Spacer(),
                if (post.isAuthor)
                  const Chip(label: Text('내가 작성함', style: TextStyle(fontSize: 11)))
                else if (post.isJoined)
                  const Chip(label: Text('참가 중', style: TextStyle(fontSize: 11, color: Colors.green))),
              ],
            ),

            const SizedBox(height: 18),
            Text(
              post.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, height: 1.3),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildInfoRow('스키장', post.resortName),
                  const Divider(height: 16),
                  _buildInfoRow('슬로프', post.slopes.join(', ')),
                  const Divider(height: 16),
                  _buildInfoRow('종목/스타일', '${post.discipline} (${post.style})'),
                  const Divider(height: 16),
                  _buildInfoRow('실력 레벨', post.skillLevel),
                  const Divider(height: 16),
                  _buildInfoRow('모집 목적', post.purpose),
                  const Divider(height: 16),
                  _buildInfoRow('일정/시간대', '${post.dateText} • ${post.timeSlot}'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('상세 설명 및 라이딩 계획', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                post.content.isNotEmpty ? post.content : '작성된 추가 설명이 없습니다.',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800, height: 1.45),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: canEnterChat ? Colors.green.shade50 : const Color(0xFF2563EB).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: canEnterChat ? Colors.green.shade200 : const Color(0xFF2563EB).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    canEnterChat ? Icons.mark_chat_unread_rounded : Icons.lock_outline_rounded,
                    size: 18,
                    color: canEnterChat ? Colors.green.shade700 : const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      canEnterChat
                          ? '현재 참여 중입니다. 하단 버튼이나 우측 플로팅 말풍선 아이콘으로 만남 위치/착장을 조율하세요!'
                          : '만남 장소와 착장 조율은 참가자 전용 대화방에서 비공개로 진행됩니다. [참가하기] 후 입장할 수 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: canEnterChat ? Colors.green.shade800 : Colors.blue.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: SafeArea(
          child: post.isExpired
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_clock_outlined, size: 16, color: Colors.grey),
                      SizedBox(width: 6),
                      Text(
                        '모집 일정이 만료되어 대화방이 자동 종료되었습니다',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : canEnterChat
                  ? Row(
                      children: [
                        if (post.isAuthor && !post.isExpired) ...[
                          Expanded(
                            flex: 4,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2563EB),
                                side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _handleBumpPost,
                              icon: const Icon(Icons.bolt_rounded, size: 18),
                              label: const Text('끌어올리기', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          flex: 6,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ChatRoomScreen(post: post)),
                              ).then((_) => setState(() {}));
                            },
                            icon: const Icon(Icons.mark_chat_unread_rounded),
                            label: const Text('대화방 열기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: post.isFull ? Colors.grey : const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: post.isFull ? null : _joinRide,
                      child: Text(
                        post.isFull ? '모집이 마감되었습니다' : '같이 타기 참가하기 (${post.currentMembers}/${post.maxMembers + 1}명)',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// 참가자 전용 대화방 화면
// -------------------------------------------------------------

class ChatRoomScreen extends StatefulWidget {
  final RidePost post;

  const ChatRoomScreen({super.key, required this.post});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>?>? _postDocSub;

  @override
  void initState() {
    super.initState();
    widget.post.unreadCount = 0;
    final unreadTotal = gRidePosts.where((p) => p.canAccessChat).fold<int>(0, (acc, p) => acc + p.unreadCount);
    gUnreadChatCountNotifier.value = unreadTotal;
    if (unreadTotal == 0) {
      NotificationService.instance.clearAllNotificationsAndBadge();
    }

    if (widget.post.id.isNotEmpty) {
      _postDocSub = AppFirebaseService.instance
          .streamGatheringDoc(widget.post.id)
          .listen((data) {
        if (!mounted || data == null) return;
        final pNames = List<String>.from(data['participantNames'] ?? []);
        final pUids = List<String>.from(data['participantUids'] ?? []);
        final membersCount = (data['currentMembers'] as num?)?.toInt() ?? pNames.length;
        final refillNeeded = (data['needsRefill'] as bool?) ?? false;

        setState(() {
          widget.post.participantNames = pNames;
          widget.post.participantUids = pUids;
          widget.post.currentMembers = membersCount;
          widget.post.needsRefill = refillNeeded;
        });
      });
    }
  }

  @override
  void dispose() {
    _postDocSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    widget.post.unreadCount = 0;
    final unreadTotal = gRidePosts.where((p) => p.canAccessChat).fold<int>(0, (acc, p) => acc + p.unreadCount);
    gUnreadChatCountNotifier.value = unreadTotal;
    if (unreadTotal == 0) {
      NotificationService.instance.clearAllNotificationsAndBadge();
    }
    super.dispose();
  }

  String _formatMessageTime(DateTime dt) {
    final period = dt.hour < 12 ? '오전' : '오후';
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$period $hour:$minute';
  }

  void _sendMessage() {
    if (widget.post.isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료된 대화방에서는 메시지를 전송할 수 없습니다.')),
      );
      return;
    }
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    if (!ensureUserLoggedIn(context, actionName: '채팅 메시지를 전송')) return;

    // 🛡️ 금칙어 & 외부 링크 실시간 필터링
    final filterError = ContentFilterService.validate(text);
    if (filterError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text(filterError),
        ),
      );
      return;
    }

    final String myNickname;
    if (widget.post.isAnonymous) {
      if (widget.post.isAuthor) {
        myNickname = '익명의라이더 A (방장)';
      } else {
        final anonJoined = widget.post.participantNames.firstWhere(
          (name) => name != widget.post.authorName && name.startsWith('익명의라이더'),
          orElse: () => '익명의라이더 B',
        );
        myNickname = anonJoined;
      }
    } else {
      myNickname = gCurrentUser?.nickname ?? '익명의 라이더';
    }

    final newMsg = ChatMessage(
      sender: myNickname,
      senderUid: gCurrentUser?.id,
      realSenderName: gCurrentUser?.nickname,
      text: text,
      time: DateTime.now(),
      isMe: true,
    );


    setState(() {
      widget.post.chatMessages.add(newMsg);
    });

    // 🚀 Firestore 실시간 메시지 전송
    if (widget.post.id.isNotEmpty) {
      AppFirebaseService.instance.sendChatMessage(widget.post.id, newMsg);
    }

    // 🔔 대화방 참가자들에게 푸시 알림 전송 (발신자 본인 기기 제외, 상대방 기기들만 수신)
    final targetParticipants = List<String>.from(widget.post.participantNames);
    if (!targetParticipants.contains(widget.post.authorName)) {
      targetParticipants.add(widget.post.authorName);
    }
    targetParticipants.remove(myNickname);

    final targetUids = List<String>.from(widget.post.participantUids);
    if (widget.post.authorUid != null &&
        widget.post.authorUid!.isNotEmpty &&
        !targetUids.contains(widget.post.authorUid)) {
      targetUids.add(widget.post.authorUid!);
    }
    final myUid = AppFirebaseService.instance.currentUid;
    targetUids.remove(myUid);

    NotificationService.instance.notifyRider(
      senderNickname: myNickname,
      targetAuthorName: widget.post.authorName,
      targetParticipants: targetParticipants,
      targetUids: targetUids.isNotEmpty ? targetUids : null,
      title: '💬 [${widget.post.resortName.split(' ')[0]}] 새 메시지',
      body: '$myNickname: $text',
      type: 'chat_message',
      postId: widget.post.id,
    );

    _msgController.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isMessageFromBlockedUser(ChatMessage msg) {
    if (msg.isMe || msg.isSystem) return false;
    final user = gCurrentUser;
    if (user == null) return false;
    if (msg.senderUid != null && msg.senderUid == user.id) return false;
    if (msg.realSenderName != null && msg.realSenderName == user.nickname) return false;
    if (msg.senderUid != null && msg.senderUid!.isNotEmpty) {
      if (user.isUserBlocked(msg.senderUid!, uid: msg.senderUid)) return true;
    }
    if (msg.realSenderName != null && msg.realSenderName!.isNotEmpty) {
      if (user.isUserBlocked(msg.realSenderName!)) return true;
    }
    if (!msg.sender.startsWith('익명의') && !msg.sender.startsWith('익명')) {
      if (user.isUserBlocked(msg.sender)) return true;
    }
    return false;
  }

  void _showBlockParticipantModal() {
    final myUid = gCurrentUser?.id ?? '';
    final String myAssignedName;
    if (widget.post.isAnonymous) {
      if (widget.post.isAuthor) {
        myAssignedName = '익명의라이더 A';
      } else {
        myAssignedName = widget.post.participantNames.firstWhere(
          (name) => name != widget.post.authorName && (name.startsWith('익명의라이더') || name.startsWith('익명의 라이더')),
          orElse: () => '',
        );
      }
    } else {
      myAssignedName = gCurrentUser?.nickname ?? '';
    }
    final myRealName = gCurrentUser?.nickname ?? '';

    final otherParticipants = <Map<String, String>>[];
    if (!widget.post.isAuthor &&
        widget.post.authorName.isNotEmpty &&
        widget.post.authorName != myAssignedName &&
        widget.post.authorName != myRealName &&
        (widget.post.authorUid == null || widget.post.authorUid != myUid)) {
      otherParticipants.add({
        'name': widget.post.authorName,
        'uid': widget.post.authorUid ?? '',
      });
    }

    for (int i = 0; i < widget.post.participantNames.length; i++) {
      final p = widget.post.participantNames[i];
      final pUid = (i < widget.post.participantUids.length) ? widget.post.participantUids[i] : '';
      if (p.isNotEmpty &&
          p != myAssignedName &&
          p != myRealName &&
          p != '나' &&
          p != '나 (방장)' &&
          (pUid.isEmpty || pUid != myUid) &&
          !otherParticipants.any((item) => item['name'] == p && item['uid'] == pUid)) {
        otherParticipants.add({
          'name': p,
          'uid': pUid,
        });
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.red, size: 22),
                  SizedBox(width: 8),
                  Text('비매너 참가자 차단 및 신고', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              const Text('차단 시 해당 사용자의 글과 후기가 숨김 처리되며, 향후 대화 및 참가 시 알림이 제공됩니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              if (otherParticipants.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('차단할 수 있는 다른 참가자가 없습니다.', style: TextStyle(color: Colors.grey))),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: otherParticipants.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = otherParticipants[index];
                      final name = item['name'] ?? '';
                      final targetUid = item['uid'] ?? '';
                      final isBlocked = (targetUid.isNotEmpty)
                          ? (gCurrentUser?.isUserBlocked(targetUid, uid: targetUid) ?? false)
                          : (gCurrentUser?.isUserBlocked(name) ?? false);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: CircleAvatar(
                          backgroundColor: isBlocked ? Colors.red.shade100 : const Color(0xFF2563EB).withValues(alpha: 0.1),
                          child: Icon(
                            isBlocked ? Icons.block_rounded : Icons.person,
                            color: isBlocked ? Colors.red.shade700 : const Color(0xFF2563EB),
                            size: 18,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            if (isBlocked) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.red.shade200, width: 0.8),
                                ),
                                child: const Text('차단됨', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () {
                            final blockTarget = targetUid.isNotEmpty ? targetUid : name;
                            setState(() {
                              if (isBlocked) {
                                gCurrentUser?.unblockUser(blockTarget);
                              } else {
                                gCurrentUser?.blockUser(blockTarget);
                              }
                              if (gCurrentUser != null) {
                                AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
                              }
                            });
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: isBlocked ? const Color(0xFF1E3A8A) : Colors.red.shade800,
                                content: Text(isBlocked ? '\'$name\' 님 차단을 해제했습니다.' : '\'$name\' 님을 차단했습니다.'),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isBlocked ? Colors.grey.shade300 : Colors.red.shade50,
                            foregroundColor: isBlocked ? Colors.black87 : Colors.red.shade700,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(isBlocked ? '차단 해제' : '차단하기', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _confirmLeaveChatRoom() {
    final isRandomMatch = widget.post.purpose.contains('랜덤') || widget.post.purpose.contains('파티 매칭');

    if (isRandomMatch) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('슬로프 파티 대화방 퇴장 경고', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🚨 지금 퇴장 시 아래 페널티가 즉시 적용됩니다:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.red),
                    ),
                    SizedBox(height: 8),
                    Text('1. ⚡ 오늘의 4인 파티 매칭 기회 즉시 소멸 (금일 재매칭 불가)', style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.35)),
                    SizedBox(height: 4),
                    Text('2. ⏱️ 향후 2시간 동안 모든 메이트 모집글 작성 및 참여 제한', style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '다른 메이트들의 소중한 라이딩 시간을 보호하기 위해 무분별한 중도 퇴장을 제한하고 있습니다.\n\n정말 대화방에서 퇴장하시겠습니까?',
                style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('계속 대화하기', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _executeLeave(isRandomMatch: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('경고 확인 후 퇴장'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('대화방 나가기', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('대화방에서 나가시겠습니까? 나가시면 참여 목록에서 제외됩니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _executeLeave(isRandomMatch: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('나가기'),
            ),
          ],
        ),
      );
    }
  }

  void _executeLeave({required bool isRandomMatch}) {
    final myNickname = gCurrentUser?.nickname ?? '익명의 라이더';
    setState(() {
      widget.post.participantNames.remove(myNickname);
      widget.post.currentMembers = (widget.post.currentMembers - 1).clamp(1, 4);
      widget.post.isJoined = false;

      final sysMsg = ChatMessage(
        sender: '시스템',
        text: isRandomMatch
            ? '⚠️ $myNickname 님이 대화방을 퇴장하셨습니다 (현재 ${widget.post.currentMembers}명).\n상단 [1명 실시간 충원] 버튼을 눌러 새 메이트를 충원할 수 있습니다 ⛷️'
            : '⚠️ $myNickname 님이 대화방을 퇴장하셨습니다.',
        time: DateTime.now(),
        isSystem: true,
      );
      widget.post.chatMessages.add(sysMsg);
      if (widget.post.id.isNotEmpty) {
        AppFirebaseService.instance.sendChatMessage(widget.post.id, sysMsg);
        AppFirebaseService.instance.toggleJoinRidePost(widget.post.id, myNickname);
      }
    });

    if (isRandomMatch) {
      gDailyRandomMatchRemaining = 0;
      gPostBanUntil = DateTime.now().add(const Duration(hours: 2));
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isRandomMatch ? Colors.red.shade800 : const Color(0xFF1E3A8A),
        content: Text(
          isRandomMatch
              ? '대화방에서 퇴장했습니다. (향후 2시간 동안 모집글 작성 및 참여가 제한됩니다)'
              : '대화방에서 퇴장했습니다.',
        ),
      ),
    );
  }


  void _confirmDeletePostAndCloseRoom() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('모집글 삭제 및 방 종료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Text('작성하신 모집글을 삭제하고 대화방을 종료하시겠습니까?\n\n삭제 시 메이트 목록에서 즉시 제거되며 모든 대화가 종료됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              if (widget.post.id.isNotEmpty) {
                await AppFirebaseService.instance.deleteRidePost(widget.post.id);
              }
              gRidePosts.removeWhere((p) => (p.id.isNotEmpty && p.id == widget.post.id) || (p.title == widget.post.title && p.authorName == widget.post.authorName));
              gRidePostsNotifier.value = List<RidePost>.from(gRidePosts);
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('모집글이 삭제되고 대화방이 종료되었습니다.'), backgroundColor: Colors.black87),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('삭제 및 종료'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isRandomMatch = widget.post.purpose.contains('랜덤') || widget.post.purpose.contains('파티 매칭');
    final bool needsRefill = isRandomMatch && widget.post.currentMembers < 4;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.post.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.post.resortName.split(' ')[0]} • 참여자 전용 (${widget.post.currentMembers}/${widget.post.maxMembers + 1}명)',
              style: const TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onSelected: (val) {
              if (val == 'block') {
                _showBlockParticipantModal();
              } else if (val == 'leave') {
                _confirmLeaveChatRoom();
              } else if (val == 'delete_post') {
                _confirmDeletePostAndCloseRoom();
              }
            },
            itemBuilder: (context) => [
              if (widget.post.isAuthor)
                const PopupMenuItem(
                  value: 'delete_post',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('모집글 삭제 및 방 종료', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('참가자 차단 및 신고', style: TextStyle(fontSize: 13, color: Colors.red)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app_rounded, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('대화방 나가기', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<ChatMessage>>(
        stream: widget.post.id.isNotEmpty
            ? AppFirebaseService.instance.streamChatMessages(widget.post.id)
            : const Stream.empty(),
        builder: (context, snapshot) {
          final displayMessages = (snapshot.hasData && snapshot.data!.isNotEmpty)
              ? snapshot.data!
              : widget.post.chatMessages;

          final myUid = gCurrentUser?.id ?? '';
          final bool hasBlockedUserInRoom = displayMessages.any((m) => _isMessageFromBlockedUser(m)) ||
              widget.post.participantUids.any((uid) => uid.isNotEmpty && uid != myUid && (gCurrentUser?.isUserBlocked(uid, uid: uid) ?? false)) ||
              (!widget.post.isAuthor && widget.post.authorUid != null && widget.post.authorUid!.isNotEmpty && widget.post.authorUid != myUid && (gCurrentUser?.isUserBlocked(widget.post.authorUid!, uid: widget.post.authorUid) ?? false));

          return Column(
            children: [
              if (hasBlockedUserInRoom)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border(bottom: BorderSide(color: Colors.red.shade200)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFDC2626)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '⚠️ 내가 차단한 사용자가 대화방에 참여 중입니다. 슬로프 만남 시 주의하세요.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFFB91C1C), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )
              else if (widget.post.isExpired)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: Colors.grey.shade200,
                  child: const Row(
                    children: [
                      Icon(Icons.lock_clock_outlined, size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '🌙 모집 일정이 만료(익일 02:00)되어 대화방이 자동 종료되었습니다.',
                          style: TextStyle(fontSize: 11.5, color: Colors.black87, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )
              else if (needsRefill)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    border: Border(bottom: BorderSide(color: Colors.amber.shade200)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.post.needsRefill ? Icons.sync_rounded : Icons.group_outlined,
                        size: 18,
                        color: const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.post.needsRefill
                                  ? '⚡ 실시간 1명 충원 대기 중 (${widget.post.currentMembers}/4명)'
                                  : '참여자 1명이 퇴장했습니다 (현재 ${widget.post.currentMembers}명)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                            ),
                            Text(
                              widget.post.needsRefill
                                  ? '다른 라이더가 파티 매칭 시작 시 이 방으로 즉시 합류합니다.'
                                  : '3명이서 타거나, 실시간으로 1명을 충원할 수 있습니다.',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final newStatus = !widget.post.needsRefill;
                          setState(() {
                            widget.post.needsRefill = newStatus;
                          });
                          if (widget.post.id.isNotEmpty) {
                            await AppFirebaseService.instance.requestRandomMatchRefill(widget.post.id, newStatus);
                          }
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: newStatus ? const Color(0xFFD97706) : Colors.grey.shade700,
                              content: Text(
                                newStatus
                                    ? '⚡ 실시간 충원 대기열에 등록되었습니다! 새 메이트가 입장하면 자동 매칭됩니다.'
                                    : '충원 요청이 취소되었습니다.',
                              ),
                            ),
                          );
                        },
                        icon: Icon(widget.post.needsRefill ? Icons.close_rounded : Icons.bolt_rounded, size: 14),
                        label: Text(
                          widget.post.needsRefill ? '충원 취소' : '1명 실시간 충원',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.post.needsRefill ? Colors.grey.shade600 : const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '참가 승인된 인원만 입장 가능한 대화방입니다. 만남 위치나 복장을 안전하게 조율하세요!',
                          style: TextStyle(fontSize: 11.5, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: displayMessages.length,
                  itemBuilder: (context, index) {
                    final msg = displayMessages[index];

                    if (msg.isSystem) {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            msg.text,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final bool isBlockedSender = _isMessageFromBlockedUser(msg);

                    final timeStr = _formatMessageTime(msg.time);
                    final timeWidget = Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (msg.isMe) timeWidget,
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
                            decoration: BoxDecoration(
                              color: isBlockedSender
                                  ? const Color(0xFFFEF2F2)
                                  : (msg.isMe ? const Color(0xFF2563EB) : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(14),
                              border: isBlockedSender
                                  ? Border.all(color: const Color(0xFFFCA5A5), width: 1.2)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                if (!msg.isMe) ...[
                                  if (isBlockedSender)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          msg.sender,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFDC2626),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEE2E2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFF87171), width: 0.8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.block_rounded, size: 9.5, color: Color(0xFFDC2626)),
                                              SizedBox(width: 2.5),
                                              Text(
                                                '차단된 사용자',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFDC2626),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      msg.sender,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  const SizedBox(height: 3),
                                ],
                                Text(
                                  msg.text,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isBlockedSender
                                        ? const Color(0xFF991B1B)
                                        : (msg.isMe ? Colors.white : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!msg.isMe) timeWidget,
                        ],
                      ),
                    );
                  },
                ),
              ),
          widget.post.isExpired
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: const SafeArea(
                    child: Center(
                      child: Text(
                        '🔒 종료된 대화방에서는 새 메시지를 전송할 수 없습니다.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: '메시지를 입력하세요 (예: 검정 자켓/흰 헬멧입니다)',
                              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                          icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------
// 글쓰기 화면
// -------------------------------------------------------------

class WriteRidePostScreen extends StatefulWidget {
  final String? initialResortName;

  const WriteRidePostScreen({super.key, this.initialResortName});

  @override
  State<WriteRidePostScreen> createState() => _WriteRidePostScreenState();
}

class _WriteRidePostScreenState extends State<WriteRidePostScreen> {
  SkiResort? _selectedResort;
  final List<String> _selectedSlopes = [];
  String _selectedDiscipline = '스키';
  String _selectedSkiStyle = '인터스키';
  String _selectedBoardStyle = '덕스탠스';
  String _selectedSkillLevel = '초급';
  String _selectedPurpose = '같이타요';

  DateTime _selectedDate = DateTime.now();
  String _selectedTimeSlot = '주간 (09~17)';
  int _selectedMemberCount = 1;
  bool _isAnonymous = true; // 🛡️ 익명 모드 (디폴트: ON)

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  final List<String> _skiStyles = ['인터스키', '프리스키'];
  final List<String> _boardStyles = ['덕스탠스', '테크니컬라이딩', '알파인'];

  final List<Map<String, String>> _skillLevels = const [
    {'level': '입문', 'desc': '관광~0년차'},
    {'level': '초급', 'desc': '1~2년차'},
    {'level': '중급', 'desc': '3~5년차'},
    {'level': '상급', 'desc': '6년차 이상'},
  ];

  final List<String> _purposes = ['같이타요', '팔로잉', '원포인트'];

  List<String> get _availableTimeSlots {
    if (_selectedResort != null && _selectedResort!.availableTimeSlots.isNotEmpty) {
      return _selectedResort!.availableTimeSlots;
    }
    return const ['주간 (09~17)', '오후 (13~17)', '야간 (18~22)', '심야 (22~02)'];
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialResortName != null && widget.initialResortName!.isNotEmpty && widget.initialResortName != '전체') {
      final match = kSkiResorts.cast<SkiResort?>().firstWhere(
        (r) => r!.shortName == widget.initialResortName || r.name.contains(widget.initialResortName!),
        orElse: () => null,
      );
      if (match != null) {
        _selectedResort = match;
      }
    }
    _selectedTimeSlot = _availableTimeSlots.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 120)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _onResortChanged(SkiResort? resort) {
    setState(() {
      _selectedResort = resort;
      _selectedSlopes.clear();

      final slots = _availableTimeSlots;
      if (!slots.contains(_selectedTimeSlot)) {
        _selectedTimeSlot = slots.first;
      }
    });
  }

  void _showFilterErrorDialog(String errorMsg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
            SizedBox(width: 8),
            Text('등록 제한 안내', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5)),
          ],
        ),
        content: Text(errorMsg, style: const TextStyle(fontSize: 13.5, height: 1.45)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (gPostBanUntil != null && DateTime.now().isBefore(gPostBanUntil!)) {
      final remainingMin = gPostBanUntil!.difference(DateTime.now()).inMinutes;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade800,
          content: Text('🚨 슬로프 파티 중도 퇴장 페널티로 인해 앞으로 ${remainingMin + 1}분 동안 모집글 작성이 제한됩니다.'),
        ),
      );
      return;
    }

    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (_selectedResort == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스키장을 선택해주세요.')));
      return;
    }
    if (_selectedSlopes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('슬로프를 1개 이상 선택해주세요.')));
      return;
    }
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목을 입력해주세요.')));
      return;
    }

    // 🛡️ 금칙어 & 외부 링크 실시간 필터링
    final titleError = ContentFilterService.validate(title);
    if (titleError != null) {
      _showFilterErrorDialog(titleError);
      return;
    }
    final contentError = ContentFilterService.validate(content);
    if (contentError != null) {
      _showFilterErrorDialog(contentError);
      return;
    }

    final String formattedDate =
        '${_selectedDate.month}월 ${_selectedDate.day}일(${_getWeekDayName(_selectedDate.weekday)})';

    final author = _isAnonymous ? '익명의라이더 A' : (gCurrentUser?.nickname ?? '나 (방장)');
    final newPost = RidePost(
      id: '',
      title: title,
      content: _contentController.text.trim(),
      resortName: _selectedResort!.name,
      slopes: List.from(_selectedSlopes),
      discipline: _selectedDiscipline,
      style: _selectedDiscipline == '스키' ? _selectedSkiStyle : _selectedBoardStyle,
      skillLevel: _selectedSkillLevel,
      purpose: _selectedPurpose,
      dateText: formattedDate,
      timeSlot: _selectedTimeSlot,
      maxMembers: _selectedMemberCount,
      currentMembers: 1,
      authorName: author,
      participantNames: [author],
      isAuthor: true,
      isJoined: true,
      isAnonymous: _isAnonymous,
      chatMessages: [
        ChatMessage(
          sender: '시스템',
          text: '[${_selectedResort!.name.split(' ')[0]} / ${_selectedSlopes.join(', ')}] 슬로프 메이트 대화방이 개설되었습니다.\n참가자들과 만남 위치나 착장(헬멧/자켓 색상)을 이곳에서 편하게 조율해보세요!',
          time: DateTime.now(),
          isSystem: true,
        ),
      ],
    );


    // 🚀 Firestore 클라우드에 실시간 저장
    AppFirebaseService.instance.createRidePost(newPost);
    gRidePosts.insert(0, newPost);

    Navigator.pop(context, true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('모집글이 클라우드에 성공적으로 등록되었습니다!')),
    );
  }

  String _getWeekDayName(int weekday) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final String formattedDate =
        '${_selectedDate.month}월 ${_selectedDate.day}일(${_getWeekDayName(_selectedDate.weekday)})';

    final List<String> currentSlots = _availableTimeSlots;
    final String safeTimeSlot = currentSlots.contains(_selectedTimeSlot)
        ? _selectedTimeSlot
        : currentSlots.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('같이타요 글쓰기'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _submit,
              child: const Text('등록', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🛡️ Apple Guideline 1.2: 안전 수칙 및 무관용(Zero-Tolerance) 원칙 고지 카드
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_rounded, color: Color(0xFFDC2626), size: 18),
                      SizedBox(width: 6),
                      Text(
                        '커뮤니티 안전 정책 및 무관용(Zero-Tolerance) 원칙',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '• 본 서비스는 만 19세(18+) 이상 성인 라이더 전용 커뮤니티입니다.\n'
                    '• 부적절한 콘텐츠(욕설, 비방, 음란물, 불법 정보) 게시 시 사전 경고 없이 즉각 삭제 처리됩니다.\n'
                    '• 악성 이용자는 무관용 원칙에 따라 24시간 이내 영구 퇴출(계정 이용 정지) 조치됩니다.\n'
                    '• 게시글 등록 시 서비스 이용약관(EULA)에 동의한 것으로 간주됩니다.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF7F1D1D), height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => showAppTermsDialog(context),
                    child: const Text(
                      '📜 서비스 이용약관(EULA) 전문 확인하기 >',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
            const Text('1. 스키장 선택', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SkiResort>(
                  isExpanded: true,
                  hint: const Text('스키장 선택', style: TextStyle(fontSize: 14)),
                  value: _selectedResort,
                  items: kSkiResorts.map((resort) {
                    return DropdownMenuItem<SkiResort>(
                      value: resort,
                      child: Text(resort.name, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: _onResortChanged,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('2. 내가 탈 슬로프 선택', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('(다중 선택 가능)', style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
                if (_selectedSlopes.isNotEmpty) ...[
                  const Spacer(),
                  Text('${_selectedSlopes.length}개 선택됨', style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (_selectedResort == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: const Text('스키장을 먼저 선택해주세요.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              )
            else ...[
              // 구역별 세부 슬로프 선택 칩 리스트
              ...() {
                final sections = {for (var s in _selectedResort!.detailedSlopes) s.section}.toList();
                return sections.map((sec) {
                  final sectionSlopes = _selectedResort!.detailedSlopes.where((s) => s.section == sec).toList();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📍 $sec', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: sectionSlopes.map((detailedSlope) {
                            final slope = detailedSlope.displayName;
                            final isSelected = _selectedSlopes.contains(slope);
                            return FilterChip(
                              avatar: CircleAvatar(
                                radius: 4,
                                backgroundColor: detailedSlope.difficulty.color,
                              ),
                              label: Text(
                                detailedSlope.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? const Color(0xFF1E3A8A) : Colors.black87,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              checkmarkColor: const Color(0xFF2563EB),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
                              ),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedSlopes.add(slope);
                                  } else {
                                    _selectedSlopes.remove(slope);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                });
              }(),
            ],
            const SizedBox(height: 16),
            const Text('3. 종목 및 스타일 선택', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDisciplineRadio('스키', '스키'),
                      _buildDisciplineRadio('보드 (스노보드)', '보드'),
                    ],
                  ),
                  const Divider(height: 10),
                  if (_selectedDiscipline == '스키')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          const SizedBox(width: 6),
                          const Text('스키:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB))),
                          const Spacer(),
                          ..._skiStyles.map((style) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: _buildStyleChip(
                                label: style,
                                isSelected: _selectedSkiStyle == style,
                                onSelected: () => setState(() => _selectedSkiStyle = style),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  if (_selectedDiscipline == '보드')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          const SizedBox(width: 6),
                          const Text('보드:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB))),
                          const Spacer(),
                          ..._boardStyles.map((style) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: _buildStyleChip(
                                label: style,
                                isSelected: _selectedBoardStyle == style,
                                onSelected: () => setState(() => _selectedBoardStyle = style),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('4. 나의 실력', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('(시즌권 연차 기준)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: _skillLevels.map((skill) {
                final isSelected = _selectedSkillLevel == skill['level'];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _selectedSkillLevel = skill['level']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF2563EB).withValues(alpha: 0.12) : Colors.white,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              skill['level']!,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF2563EB) : Colors.black87),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              skill['desc']!,
                              style: TextStyle(fontSize: 10, color: isSelected ? const Color(0xFF1E40AF) : Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('5. 목적 설정', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _purposes.map((purpose) {
                  final isSelected = _selectedPurpose == purpose;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _selectedPurpose = purpose),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<String>(
                            value: purpose,
                            groupValue: _selectedPurpose,
                            activeColor: const Color(0xFF2563EB),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedPurpose = val);
                            },
                          ),
                          const SizedBox(width: 4),
                          Text(
                            purpose,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF2563EB) : Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('6. 일정 및 시간대', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF2563EB)),
                  label: Text(formattedDate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: safeTimeSlot,
                        items: currentSlots.map((slot) {
                          return DropdownMenuItem(value: slot, child: Text(slot, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedTimeSlot = val);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('7. 모집 인원', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                const Text('(본인 제외, 최대 3명)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                Row(
                  children: [1, 2, 3].map((count) {
                    final isSelected = _selectedMemberCount == count;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: ChoiceChip(
                        label: Text('$count명', style: const TextStyle(fontSize: 12.5)),
                        selected: isSelected,
                        selectedColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300),
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedMemberCount = count);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('8. 제목 및 상세 설명', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '제목을 직접 입력해주세요',
                hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '간단한 라이딩 소개를 적어주세요. (구체적인 만남 위치/착장은 참여 승인 후 전용 대화방에서 조율합니다)',
                hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            const Text('9. 익명 모드 설정', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isAnonymous ? const Color(0xFF2563EB).withValues(alpha: 0.06) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isAnonymous ? const Color(0xFF2563EB).withValues(alpha: 0.3) : Colors.grey.shade300,
                  width: _isAnonymous ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isAnonymous ? const Color(0xFF2563EB).withValues(alpha: 0.15) : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isAnonymous ? Icons.shield_rounded : Icons.person_outline_rounded,
                      color: _isAnonymous ? const Color(0xFF2563EB) : Colors.grey.shade700,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '익명 모드로 등록',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isAnonymous,
                    activeTrackColor: const Color(0xFF2563EB),
                    activeThumbColor: Colors.white,
                    onChanged: (val) {
                      setState(() {
                        _isAnonymous = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '* 익명 모드로 등록하더라도 고유 식별자(UID)를 통해 신고/차단 및 24시간 이내 운영자 무관용(Zero-Tolerance) 제재 조치가 엄격히 적용됩니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
            ),
            const SizedBox(height: 32),

          ],
        ),
      ),
    );
  }

  Widget _buildDisciplineRadio(String label, String value) {
    final isSelected = _selectedDiscipline == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedDiscipline = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<String>(
              value: value,
              groupValue: _selectedDiscipline,
              activeColor: const Color(0xFF2563EB),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) {
                if (val != null) setState(() => _selectedDiscipline = val);
              },
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF2563EB) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: isSelected,
      selectedColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      side: BorderSide(color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300),
      onSelected: (_) => onSelected(),
    );
  }
}