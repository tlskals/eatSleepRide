import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '같이 타요',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// -------------------------------------------------------------
// 🏂 대형 브랜드 스플래시 화면 (선명한 로고 & 문구)
// -------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();

    // 🚀 파이어베이스 익명 인증 및 유저 프로필 초기화 + 데이터 시딩
    AppFirebaseService.instance.initUserAuthAndProfile().then((_) {
      AppFirebaseService.instance.seedInitialDataIfEmpty(gRidePosts, gRideReviews);
    });

    // 🔔 푸시 알림 및 로컬 알림 서비스 초기화 (권한 요청 및 토큰 등록)
    NotificationService.instance.initialize();

    // 사용자가 로고와 안내 문구를 여유 있게 인지할 수 있도록 1.8초 동안 유지
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Image.asset(
            'assets/logos/splash_complete_large.png',
            width: 360,
            height: 360,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 데이터 모델
// -------------------------------------------------------------

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

    if (forecasts.isEmpty) {
      forecasts = _createDefault5DayForecasts(temp);
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

  static List<DailyWeatherForecast> _createDefault5DayForecasts(double baseTemp) {
    return [
      DailyWeatherForecast(date: '오늘', dayName: '오늘 (수)', maxTemp: baseTemp + 2.0, minTemp: baseTemp - 3.5, snowfall: 0.0, weatherDesc: '맑음', iconEmoji: '☀️'),
      DailyWeatherForecast(date: '내일', dayName: '내일 (목)', maxTemp: baseTemp + 0.5, minTemp: baseTemp - 5.0, snowfall: 3.5, weatherDesc: '눈 ❄️', iconEmoji: '❄️'),
      DailyWeatherForecast(date: 'D+2', dayName: '금요일', maxTemp: baseTemp - 1.0, minTemp: baseTemp - 7.2, snowfall: 5.0, weatherDesc: '파우더 강설 ❄️', iconEmoji: '❄️'),
      DailyWeatherForecast(date: 'D+3', dayName: '토요일', maxTemp: baseTemp + 1.2, minTemp: baseTemp - 4.0, snowfall: 0.0, weatherDesc: '구름조금', iconEmoji: '⛅'),
      DailyWeatherForecast(date: 'D+4', dayName: '일요일', maxTemp: baseTemp + 3.0, minTemp: baseTemp - 2.5, snowfall: 0.0, weatherDesc: '맑음', iconEmoji: '☀️'),
    ];
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

  double get effectiveMapX {
    if (mapX != 0.5) return mapX;
    final h = (name.hashCode.abs() % 100) / 100.0;
    if (section.contains('불새마루') || section.contains('초급') || section.contains('알파') || section.contains('마운틴') || section.contains('드림')) {
      return 0.20 + h * 0.22;
    } else if (section.contains('중급') || section.contains('브라보') || section.contains('헤라') || section.contains('글로리')) {
      return 0.42 + h * 0.18;
    } else if (section.contains('익스트림') || section.contains('파크')) {
      return 0.35 + h * 0.25;
    } else {
      return 0.62 + h * 0.22;
    }
  }

  double get effectiveMapY {
    if (mapY != 0.5) return mapY;
    final h = ((name.length * 31).hashCode.abs() % 100) / 100.0;
    if (difficulty == SlopeDifficulty.beginner) {
      return 0.72 + h * 0.12;
    } else if (difficulty == SlopeDifficulty.novice) {
      return 0.62 + h * 0.12;
    } else if (difficulty == SlopeDifficulty.intermediate) {
      return 0.45 + h * 0.14;
    } else if (difficulty == SlopeDifficulty.advanced) {
      return 0.30 + h * 0.14;
    } else if (difficulty == SlopeDifficulty.park) {
      return 0.65 + h * 0.12;
    } else {
      return 0.16 + h * 0.14;
    }
  }
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
  final List<SkiWebcam> webcams;
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
    required this.webcams,
    this.icon = Icons.snowboarding_rounded,
    this.themeColor = const Color(0xFF2563EB),
  });

  List<String> get slopes => detailedSlopes.map((s) => s.displayName).toList();
  String get logoAsset => 'assets/logos/$id.png';
  String get trailMapAsset => 'assets/trailmaps/$id.png';
}

class ChatMessage {
  final String sender;
  final String text;
  final DateTime time;
  final bool isMe;
  final bool isSystem;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.time,
    this.isMe = false,
    this.isSystem = false,
  });
}

class RidePost {
  final String id;
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
  bool isJoined;
  bool isAuthor;
  final List<ChatMessage> chatMessages;

  // 🚨 실시간 신고 및 3회 누적 자동 블라인드
  int reportCount;
  bool isBlinded;
  List<String> reportedUserIds;

  RidePost({
    required this.id,
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
    this.isJoined = false,
    this.isAuthor = false,
    required this.chatMessages,
    this.reportCount = 0,
    this.isBlinded = false,
    List<String>? reportedUserIds,
  })  : participantNames = participantNames ?? [authorName],
        reportedUserIds = reportedUserIds ?? [];

  bool get isFull => currentMembers >= (maxMembers + 1);
  bool get canAccessChat => isAuthor || isJoined;
  bool get shouldHide => isBlinded || reportCount >= 3;
}

// -------------------------------------------------------------
// OAuth 소셜 인증 및 사용자 프로필 모델 (카카오, 네이버, 애플 전용)
// -------------------------------------------------------------

enum SocialAuthProvider {
  kakao,
  naver,
  apple,
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
  List<RiderBadge> badges; // 획득 배지 목록
  List<String> blockedUsers; // 차단한 사용자 닉네임 목록

  UserProfile({
    required this.id,
    required this.provider,
    required this.email,
    required this.nickname,
    this.preferredDiscipline = '스노보드',
    this.homeResort = '비발디파크',
    this.level = '중급',
    required this.joinedAt,
    this.completedRidesCount = 7,
    this.taggedReviewsCount = 4,
    this.snowPoints = 1450,
    this.riderTitle = '골드 라이더 🏂',
    List<RiderBadge>? badges,
    List<String>? blockedUsers,
  })  : badges = badges ?? [
          const RiderBadge(
            id: 'first_ride',
            title: '첫 동행 성사',
            emoji: '⛷️',
            description: '첫 같이타요 슬로프 동행을 마쳤어요',
            isUnlocked: true,
            unlockedDate: '2026.01.18',
          ),
          const RiderBadge(
            id: 'random_master',
            title: '4인 매칭 마스터',
            emoji: '⚡️',
            description: '4인 랜덤 매칭을 3회 이상 완료했어요',
            isUnlocked: true,
            unlockedDate: '2026.02.04',
          ),
          const RiderBadge(
            id: 'powder_expert',
            title: '설질 감별사',
            emoji: '❄️',
            description: '슬로프 사진과 설질 후기를 3회 이상 작성했어요',
            isUnlocked: true,
            unlockedDate: '2026.02.12',
          ),
          const RiderBadge(
            id: 'night_rider',
            title: '야간 라이더',
            emoji: '🌙',
            description: '야간/심야 슬로프 동행을 완료했어요',
            isUnlocked: true,
            unlockedDate: '2026.02.20',
          ),
          const RiderBadge(
            id: 'manner_king',
            title: '매너왕 메이트',
            emoji: '👑',
            description: '슬로프 매너왕이 되어보세요',
            isUnlocked: false,
          ),
          const RiderBadge(
            id: 'all_resorts',
            title: '전국 정복자',
            emoji: '🏔️',
            description: '전국 5개 이상 스키장에서 동행 시 획득',
            isUnlocked: false,
          ),
        ],
        blockedUsers = blockedUsers ?? [];

  String get providerDisplayName {
    switch (provider) {
      case SocialAuthProvider.kakao:
        return '카카오 계정 연동';
      case SocialAuthProvider.naver:
        return '네이버 계정 연동';
      case SocialAuthProvider.apple:
        return 'Apple ID 연동';
    }
  }

  Color get providerColor {
    switch (provider) {
      case SocialAuthProvider.kakao:
        return const Color(0xFFFEE500);
      case SocialAuthProvider.naver:
        return const Color(0xFF03C75A);
      case SocialAuthProvider.apple:
        return Colors.black;
    }
  }

  Color get providerTextColor {
    switch (provider) {
      case SocialAuthProvider.kakao:
        return const Color(0xFF191919);
      case SocialAuthProvider.naver:
      case SocialAuthProvider.apple:
        return Colors.white;
    }
  }

  bool isUserBlocked(String nickname) {
    if (nickname.isEmpty) return false;
    final cleanInput = nickname.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
    return blockedUsers.any((blocked) {
      final cleanBlocked = blocked.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
      return cleanBlocked == cleanInput || blocked.toLowerCase() == nickname.toLowerCase();
    });
  }

  void blockUser(String nickname) {
    final clean = nickname.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    if (!blockedUsers.contains(nickname)) {
      blockedUsers.add(nickname);
    }
    if (clean.isNotEmpty && !blockedUsers.contains(clean)) {
      blockedUsers.add(clean);
    }
  }

  void unblockUser(String nickname) {
    final clean = nickname.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
    blockedUsers.removeWhere((b) {
      final cleanB = b.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase();
      return b == nickname || cleanB == clean || b.toLowerCase() == nickname.toLowerCase();
    });
  }
}

// 기본 로그인 사용자 (전역 상태)
UserProfile? gCurrentUser = UserProfile(
  id: 'user_kakao_9482',
  provider: SocialAuthProvider.kakao,
  email: 'rider***@kakao.com',
  nickname: '익명의라이더#9482',
  preferredDiscipline: '스노보드',
  homeResort: '비발디파크',
  level: '중급',
  joinedAt: DateTime(2026, 1, 15),
  completedRidesCount: 7,
  taggedReviewsCount: 4,
  snowPoints: 1450,
  riderTitle: '골드 라이더 🏂',
);

// 1일 랜덤 매칭 횟수 제한 (클린한 만남 & 어뷰징 방지)
int gDailyRandomMatchLimit = 1;
int gDailyRandomMatchRemaining = 1;

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

  // 🚨 실시간 신고 및 3회 누적 자동 블라인드
  int reportCount;
  bool isBlinded;
  List<String> reportedUserIds;

  RideReview({
    required this.id,
    required this.authorName,
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

  bool get shouldHide => isBlinded || reportCount >= 3;
}

// -------------------------------------------------------------
// 🛡️ 금칙어 & 외부 링크 실시간 자동 필터링 서비스
// -------------------------------------------------------------

class ContentFilterService {
  // 음란/도박/불법 대출 금칙어 목록
  static const List<String> _bannedKeywords = [
    '조건만남', '성인용품', '출장샵', '원나잇', '애인대행', '유흥', '섹스', '야동', '오프녀',
    '바카라', '카지노', '사설토토', '토토사이트', '릴게임', '홀덤펍광고', '불법대출', '코인리딩',
    '고수익알바', '입금요구', '몸캠', '비아그라', '마약', '대마',
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
                            '안전한 슬로프 문화를 위해 서로 다른 라이더 3명의 신고가 누적되면 해당 게시글은 24시간 실시간 무인 자동 블라인드(숨김) 처리됩니다.',
                            style: TextStyle(fontSize: 11, color: Colors.red, height: 1.35),
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

List<RideReview> gRideReviews = [
  RideReview(
    id: 'rev_1',
    authorName: '익명의라이더#8192',
    resortName: '모나용평 (평창)',
    snowCondition: '극상 파우더 ❄️',
    rating: 5,
    content: '오늘 4인 랜덤매칭으로 만난 메이트분들과 메가그린이랑 레드 탔는데 설질 진짜 미쳤습니다 ㅠㅠ 다들 친절하셔서 인생샷도 찍어주시고 꿀잼이었어요! 다음 주에 또 봬요 🙌',
    photoLabels: ['용평 레드 정상 파우더 뷰 ❄️', '4인 메이트 슬로프 단체샷 🏂'],
    tags: ['#4인랜덤매칭후기', '#용평레드', '#설질대박', '#오후라이딩'],
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    likeCount: 24,
    commentCount: 5,
  ),
  RideReview(
    id: 'rev_2',
    authorName: '익명의라이더#4120',
    resortName: '비발디파크 (홍천)',
    snowCondition: '야간 압설 굿 🎿',
    rating: 5,
    content: '퇴근하고 비발디 야간 땡보딩 왔습니다! 테크노 슬로프 사람도 많이 없고 엣지 촥촥 박히네요 ㅎㅎ 같이타요 모집글 보고 합류했는데 시간 가는 줄 몰랐네요.',
    photoLabels: ['비발디 테크노 야간 조명 🌙', '베이스 스키하우스 앞 ☕️'],
    tags: ['#비발디야간', '#테크노', '#퇴근보딩', '#메이트모임'],
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    likeCount: 18,
    commentCount: 3,
  ),
  RideReview(
    id: 'rev_3',
    authorName: '익명의라이더#1055',
    resortName: '곤지암리조트 (광주)',
    snowCondition: '설질 쾌적 ☀️',
    rating: 4,
    content: '윈디 상단 뷰 최고입니다. 평일 주간이라 리프트 대기 0초! 커피 한잔 마시고 2차전 갑니다 ☕️ 다들 안전 라이딩하세요!',
    photoLabels: ['곤지암 윈디 슬로프 전경 🏔️'],
    tags: ['#곤지암주간', '#윈디슬로프', '#스키메이트'],
    createdAt: DateTime.now().subtract(const Duration(hours: 9)),
    likeCount: 15,
    commentCount: 2,
  ),
];

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
      DetailedSlope(name: '하늬', section: '베이스/초급', difficulty: SlopeDifficulty.beginner, length: '460m', note: '초심자 전용 와이드 슬로프'),
      DetailedSlope(name: '휘슬', section: '초중급', difficulty: SlopeDifficulty.novice, length: '850m', note: '완만하고 넓은 초중급 코스'),
      DetailedSlope(name: '와이낫 (Why Not)', section: '중급', difficulty: SlopeDifficulty.intermediate, length: '750m', note: '곤지암 대표 중급 카빙'),
      DetailedSlope(name: '그램 (Gram)', section: '중급', difficulty: SlopeDifficulty.intermediate, length: '680m', note: '다이나믹 롤러코스터 지형'),
      DetailedSlope(name: '윈디 (Windy)', section: '정상/중상급', difficulty: SlopeDifficulty.advanced, length: '1,429m', note: '정상 쉼터 뷰 & 롱 크루징'),
      DetailedSlope(name: '제타 1 (Zeta 1)', section: '정상/상급', difficulty: SlopeDifficulty.expert, length: '980m', note: '상급 인터스키 기술선수권 코스'),
      DetailedSlope(name: '제타 2 (Zeta 2)', section: '상급', difficulty: SlopeDifficulty.expert, status: SlopeStatus.mogul, length: '850m', note: '모굴 전용 라인'),
      DetailedSlope(name: '게일 (Gale)', section: '정상/최상급', difficulty: SlopeDifficulty.extreme, length: '1,050m', note: '곤지암 최고 경사 절벽 사면'),
      DetailedSlope(name: '곤지암 펀파크', section: '파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '400m', note: '웨이브 & 비기너 키커 존'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18~22)', '심야 (22~02)'],
    webcams: [
      SkiWebcam(name: '윈디/제타 상급 정상', location: '해발 500m 정상 쉼터', streamUrl: 'https://www.konjiamresort.co.kr'),
      SkiWebcam(name: '휘슬/하늬 초중급', location: '슬로프 중앙 합류점', streamUrl: 'https://www.konjiamresort.co.kr'),
      SkiWebcam(name: '시계탑 메인 베이스', location: '리프트 탑승장 광장', streamUrl: 'https://www.konjiamresort.co.kr'),
    ],
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
    webcams: [
      SkiWebcam(name: '재즈(Jazz) 중급 슬로프', location: '재즈 리프트 상단', streamUrl: 'https://www.sonohotelsresorts.com'),
      SkiWebcam(name: '발라드(Ballad) 초급 슬로프', location: '발라드 탑승장 앞', streamUrl: 'https://www.sonohotelsresorts.com'),
      SkiWebcam(name: '테크노/락 상급 정상', location: '매봉산 정상 휴게소', streamUrl: 'https://www.sonohotelsresorts.com'),
    ],
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
      DetailedSlope(name: '레인보우 파라다이스', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.novice, length: '5,600m', note: '국내 최장 힐링 롱코스 파노라마'),
      DetailedSlope(name: '레인보우 1 (골드)', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, length: '1,200m', note: '월드컵 알파인 공인 레이스 코스'),
      DetailedSlope(name: '레인보우 2', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, length: '1,150m', note: '레인보우 메인 급경사 직벽'),
      DetailedSlope(name: '레인보우 3', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, status: SlopeStatus.mogul, length: '1,050m', note: '대한민국 봄 시즌 모굴의 성지'),
      DetailedSlope(name: '레인보우 4', section: '발왕산 정상 (1,458m)', difficulty: SlopeDifficulty.extreme, length: '1,300m', note: '파우더 설질 & 테크니컬'),
      DetailedSlope(name: '골드밸리', section: '골드 구역', difficulty: SlopeDifficulty.advanced, length: '1,655m', note: '용평 최고의 인터스키 고속 카빙'),
      DetailedSlope(name: '골드파라다이스', section: '골드 구역', difficulty: SlopeDifficulty.intermediate, length: '1,450m', note: '쾌적하고 넓은 와이드 중급'),
      DetailedSlope(name: '골드환타지', section: '골드 구역', difficulty: SlopeDifficulty.advanced, length: '1,200m', note: '골드 리프트 상단 롤러코스터'),
      DetailedSlope(name: '레드 (Red)', section: '레드/실버 구역', difficulty: SlopeDifficulty.expert, length: '950m', note: '야간 메인 상급 슬로프 & 카빙'),
      DetailedSlope(name: '뉴레드 (New Red)', section: '레드/실버 구역', difficulty: SlopeDifficulty.expert, length: '850m', note: '레드 리프트 좌측 급사면'),
      DetailedSlope(name: '실버 (Silver)', section: '레드/실버 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '1,000m', note: '자연설 파우더 구역'),
      DetailedSlope(name: '메가그린 (Mega Green)', section: '베이스 구역', difficulty: SlopeDifficulty.novice, length: '700m', note: '국내 최대 폭 180m 광폭 슬로프'),
      DetailedSlope(name: '핑크 (Pink)', section: '베이스 구역', difficulty: SlopeDifficulty.novice, length: '650m', note: '초중급 롱턴 & 숏턴 연습'),
      DetailedSlope(name: '옐로우 (Yellow)', section: '베이스 구역', difficulty: SlopeDifficulty.beginner, length: '550m', note: '비기너 강습 전용'),
      DetailedSlope(name: '드래곤 파크', section: '파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '450m', note: '지빙 기물 & 미니 키커'),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (19:00~22:00)'],
    webcams: [
      SkiWebcam(name: '발왕산 드래곤피크 (1,458m)', location: '레인보우 최정상', streamUrl: 'https://www.yongpyong.co.kr'),
      SkiWebcam(name: '골드/레드 중상급 슬로프', location: '골드 스낵 앞', streamUrl: 'https://www.yongpyong.co.kr'),
      SkiWebcam(name: '메가그린 대형 슬로프', location: '메가그린 리프트', streamUrl: 'https://www.yongpyong.co.kr'),
    ],
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
      DetailedSlope(name: '불새마루 도도 (Dodo)', section: '불새마루 구역', difficulty: SlopeDifficulty.advanced, length: '1,100m', note: '스노우보더 인기 카빙 명소'),
      DetailedSlope(name: '불새마루 듀크 (Duke)', section: '불새마루 구역', difficulty: SlopeDifficulty.intermediate, length: '950m', note: '중급 턴 & 엣징 연습'),
      DetailedSlope(name: '불새마루 키위 (Kiwi)', section: '불새마루 구역', difficulty: SlopeDifficulty.intermediate, length: '750m', note: '불새마루 우회 코스'),
      DetailedSlope(name: '스패로우 (Sparrow)', section: '불새마루 구역', difficulty: SlopeDifficulty.beginner, length: '920m', note: '넓은 폭의 완만한 초급 코스'),
      DetailedSlope(name: '펭귄 (Penguin)', section: '불새마루 구역', difficulty: SlopeDifficulty.beginner, length: '650m', note: '메인 스키하우스 베이스 직결'),
      DetailedSlope(name: '호크 1 (Hawk 1)', section: '불새마루 구역', difficulty: SlopeDifficulty.novice, length: '1,050m', note: '휘팍 최고의 야간 라이딩 명소'),
      DetailedSlope(name: '호크 2 (Hawk 2)', section: '불새마루 구역', difficulty: SlopeDifficulty.intermediate, length: '800m', note: '호크 리프트 직하강 중급'),
      DetailedSlope(name: '파노라마 (Panorama)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.novice, length: '2,400m', note: '몽블랑에서 베이스까지 2.4km 파노라마'),
      DetailedSlope(name: '챔피온 (Champion)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.expert, length: '1,000m', note: '정통 알파인 급경사 카빙'),
      DetailedSlope(name: '디지 (Dizzy)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.extreme, length: '850m', note: '휘닉스 최고 난이도 직벽 사면'),
      DetailedSlope(name: '밸리 (Valley)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.advanced, length: '1,120m', note: '몽블랑에서 밸리로 이어지는 다운힐'),
      DetailedSlope(name: '환타지아 (Fantasia)', section: '몽블랑 정상 (1,050m)', difficulty: SlopeDifficulty.expert, length: '900m', note: '정상 쉼터 우측 테크니컬'),
      DetailedSlope(name: '슬로프스타일 (익스트림 파크)', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '600m', note: '국내 1위 익스트림 파크 키커 & 지빙 레일'),
      DetailedSlope(name: '슈퍼 하프파이프', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '160m', note: '국제 규격 높이 6.8m 슈퍼파이프'),
      DetailedSlope(name: '펀파크 & 웨이브존', section: '익스트림 파크', difficulty: SlopeDifficulty.novice, status: SlopeStatus.park, length: '450m', note: '초중급자 파크 입문 및 뱅크드 슬라럼'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18~22)', '심야 (22~24)'],
    webcams: [
      SkiWebcam(name: '몽블랑 정상 (해발 1,050m)', location: '곤돌라 정상 정류장', streamUrl: 'https://phoenixhnr.co.kr'),
      SkiWebcam(name: '호크 / 익스트림 파크', location: '파크 키커/지빙 구역', streamUrl: 'https://phoenixhnr.co.kr'),
      SkiWebcam(name: '펭귄 초급 베이스', location: '스키하우스 정면 광장', streamUrl: 'https://phoenixhnr.co.kr'),
    ],
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
      DetailedSlope(name: '빅토리아 1', section: '빅토리아 구역 (백운산 1,340m)', difficulty: SlopeDifficulty.extreme, length: '1,439m', note: '하이원 최고 경사 절벽 카빙 사면'),
      DetailedSlope(name: '빅토리아 2', section: '빅토리아 구역 (백운산 1,340m)', difficulty: SlopeDifficulty.expert, status: SlopeStatus.mogul, length: '1,300m', note: '상단 모굴 전용 코스'),
      DetailedSlope(name: '빅토리아 3', section: '빅토리아 구역 (백운산 1,340m)', difficulty: SlopeDifficulty.extreme, status: SlopeStatus.closed, length: '1,150m', note: '영구 폐쇄 / 미운영 (안전 사유)'),
      DetailedSlope(name: '헤라 1', section: '헤라 구역 (마운틴탑)', difficulty: SlopeDifficulty.intermediate, length: '1,504m', note: '마운틴탑~허브 최고의 광폭 크루징'),
      DetailedSlope(name: '헤라 2', section: '헤라 구역 (마운틴탑)', difficulty: SlopeDifficulty.advanced, status: SlopeStatus.mogul, length: '1,230m', note: '시즌 후반 모굴 & 테크니컬 전용 운영'),
      DetailedSlope(name: '헤라 3', section: '헤라 구역 (마운틴탑)', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '1,100m', note: '헤라 리프트 상단 급사면'),
      DetailedSlope(name: '아폴로 1', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, length: '1,803m', note: '밸리탑 직벽 레이스 코스'),
      DetailedSlope(name: '아폴로 2', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, length: '1,250m', note: '밸리허브 연결 상급 코스'),
      DetailedSlope(name: '아폴로 3', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.advanced, length: '1,400m', note: '아폴로 리프트 연결 중상급'),
      DetailedSlope(name: '아폴로 4', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, length: '1,550m', note: '스프링 시즌 마지막까지 단독 오픈하는 전설의 슬로프'),
      DetailedSlope(name: '아폴로 6', section: '아폴로 구역 (밸리탑)', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '1,180m', note: '밸리콘도 직결로'),
      DetailedSlope(name: '아테나 1', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,700m', note: '마운틴탑~마운틴허브 완만코스'),
      DetailedSlope(name: '아테나 2', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.novice, length: '1,670m', note: '마운틴허브~마운틴베이스 롱코스'),
      DetailedSlope(name: '아테나 3', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,200m', note: '마운틴베이스 연결 코스'),
      DetailedSlope(name: '제우스 1', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '2,329m', note: '밸리탑~밸리허브 롱코스 초보자 천국'),
      DetailedSlope(name: '제우스 2', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,840m', note: '밸리허브~밸리베이스 광폭 슬로프'),
      DetailedSlope(name: '제우스 3', section: '아테나/제우스 구역', difficulty: SlopeDifficulty.beginner, length: '1,020m', note: '제우스 우회 완경사'),
    ],
    availableTimeSlots: ['주간 (09~16)', '오후 (12~16)', '야간 (18~22)'],
    webcams: [
      SkiWebcam(name: '마운틴 탑 (해발 1,340m)', location: '회전전망대 정상', streamUrl: 'https://www.high1.com'),
      SkiWebcam(name: '헤라/아폴로 중상급', location: '마운틴 허브 환승장', streamUrl: 'https://www.high1.com'),
      SkiWebcam(name: '밸리 베이스 광장', location: '밸리 콘도 스키하우스', streamUrl: 'https://www.high1.com'),
    ],
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
      DetailedSlope(name: '알파 1 (A1)', section: '알파/베이스', difficulty: SlopeDifficulty.beginner, length: '700m', note: '메인 베이스 초급 코스'),
      DetailedSlope(name: '알파 2, 3 (A2/A3)', section: '알파/베이스', difficulty: SlopeDifficulty.beginner, length: '600m', note: '초보 연습 전용'),
      DetailedSlope(name: '브라보 1 (B1)', section: '브라보 구역', difficulty: SlopeDifficulty.intermediate, length: '1,100m', note: '웰리힐리 대표 고속 카빙 슬로프'),
      DetailedSlope(name: '브라보 2 (B2)', section: '브라보 구역', difficulty: SlopeDifficulty.intermediate, length: '950m', note: '브라보 리프트 상단 와이드'),
      DetailedSlope(name: '에코 1, 2 (E1/E2)', section: '에코 구역', difficulty: SlopeDifficulty.intermediate, length: '900m', note: '술이봉 곤돌라 하단 연결'),
      DetailedSlope(name: '챌린지 1, 2 (C1/C2)', section: '챌린지 구역', difficulty: SlopeDifficulty.expert, length: '850m', note: '상급 인터스키 게렌데'),
      DetailedSlope(name: '챌린지 4, 5 (C4/C5)', section: '챌린지 구역', difficulty: SlopeDifficulty.extreme, status: SlopeStatus.mogul, length: '950m', note: 'C5 모굴 라인 & 급경사'),
      DetailedSlope(name: '스타익스프레스', section: '관광 롱코스', difficulty: SlopeDifficulty.novice, length: '2,100m', note: '술이봉 정상에서 이어지는 2.1km 롱코스'),
      DetailedSlope(name: '웰리 펀파크', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '650m', note: '국내 최장 규모 펀파크 키커 & 지빙 라인'),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (18:30~22:30)', '심야 (22:30~24:00)'],
    webcams: [
      SkiWebcam(name: '술이봉 정상 (해발 890m)', location: '곤돌라 정상 하차장', streamUrl: 'https://www.wellihillipark.com'),
      SkiWebcam(name: '브라보 / 챌린지 슬로프', location: 'D 리프트 상단', streamUrl: 'https://www.wellihillipark.com'),
      SkiWebcam(name: '메인 베이스 광장', location: '본관 스키하우스 앞', streamUrl: 'https://www.wellihillipark.com'),
    ],
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
      DetailedSlope(name: '1번 슬로프', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '950m', note: '메인 베이스 연결 와이드 슬로프'),
      DetailedSlope(name: '1-1번 슬로프', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '300m', note: '초심자 전용 입문 강습장'),
      DetailedSlope(name: '2번 슬로프 (오렌지)', section: '초중급 구역', difficulty: SlopeDifficulty.novice, length: '700m', note: '중벌 고속 리프트 연결 코스'),
      DetailedSlope(name: '3번 슬로프 (뉴오렌지)', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '900m', note: '중급 카빙 & 다이나믹 웨이브'),
      DetailedSlope(name: '5번 슬로프 (구 블루/실버)', section: '상급 구역', difficulty: SlopeDifficulty.advanced, length: '1,100m', note: '지산 최고의 고속 카빙 메인 슬로프'),
      DetailedSlope(name: '6번 슬로프', section: '상급 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '800m', note: '연결 및 안전 전용로'),
      DetailedSlope(name: '7번 슬로프 (구 블랙)', section: '최상급 구역', difficulty: SlopeDifficulty.extreme, length: '950m', note: '지산 최고 경사도 절벽 & 모굴 코스'),
      DetailedSlope(name: '지산 익스트림 파크', section: '익스트림 파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '500m', note: '수도권 최강 3단 키커 및 레일/박스 지빙'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18:30~23:00)', '심야 (23:00~02:00)'],
    webcams: [
      SkiWebcam(name: '5번 / 7번 상급 슬로프', location: '고속 리프트 상단', streamUrl: 'https://www.jisanresort.co.kr'),
      SkiWebcam(name: '3번 중급 슬로프', location: '중앙 쉼터 앞', streamUrl: 'https://www.jisanresort.co.kr'),
      SkiWebcam(name: '1번 초급 및 메인 광장', location: '만남의 광장 시계탑', streamUrl: 'https://www.jisanresort.co.kr'),
    ],
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
      DetailedSlope(name: '드림 1, 2 (Dream)', section: '드림 구역', difficulty: SlopeDifficulty.beginner, length: '1,100m', note: '완만하고 아늑한 숲속 힐링 코스'),
      DetailedSlope(name: '해피 (Happy)', section: '해피 구역', difficulty: SlopeDifficulty.novice, length: '2,150m', note: '함백산 능선 2.1km 롱코스'),
      DetailedSlope(name: '글로리 1, 2 (Glory)', section: '글로리 구역', difficulty: SlopeDifficulty.intermediate, length: '1,400m', note: '천연 파우더 설질 중급 카빙'),
      DetailedSlope(name: '챌린지 (Challenge)', section: '챌린지 구역', difficulty: SlopeDifficulty.expert, length: '900m', note: '오투 타워 정상 급경사 다운힐'),
      DetailedSlope(name: '패션 (Passion)', section: '상급 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.closed, length: '750m', note: '고난이도 테크니컬 코스'),
    ],
    availableTimeSlots: ['주간 (09~16:30)', '오후 (12:30~16:30)', '야간 (18~21:30)'],
    webcams: [
      SkiWebcam(name: '함백산 정상 뷰 (1,420m)', location: '오투 타워 정상', streamUrl: 'https://www.o2resort.com'),
      SkiWebcam(name: '글로리/해피 슬로프', location: '슬로프 분기점', streamUrl: 'https://www.o2resort.com'),
    ],
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
      DetailedSlope(name: '팬더 (Panda)', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '500m', note: '메인 스키하우스 앞 광폭 슬로프'),
      DetailedSlope(name: '래빗 (Rabbit)', section: '초급 구역', difficulty: SlopeDifficulty.beginner, length: '350m', note: '초심자 전용 강습장'),
      DetailedSlope(name: '드래곤 (Dragon)', section: '초중급 구역', difficulty: SlopeDifficulty.novice, length: '1,050m', note: '백양리 전철역 뷰 롱 크루징'),
      DetailedSlope(name: '디어 (Deer)', section: '중급 구역', difficulty: SlopeDifficulty.intermediate, length: '900m', note: '엘리시안 대표 중급 카빙'),
      DetailedSlope(name: '퓨마 (Puma)', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '750m', note: '알프스 하우스 방면 급경사'),
      DetailedSlope(name: '페가수스 (Pegasus)', section: '상급 구역', difficulty: SlopeDifficulty.expert, length: '850m', note: '엘리시안 최고 난이도 테크니컬 코스'),
      DetailedSlope(name: '강촌 익스트림 파크', section: '파크', difficulty: SlopeDifficulty.park, status: SlopeStatus.park, length: '400m', note: '박스, 레일, 미니 키커'),
    ],
    availableTimeSlots: ['주간 (09~17)', '오후 (13~17)', '야간 (18:30~22:30)', '심야 (22:30~03:00)'],
    webcams: [
      SkiWebcam(name: '드래곤/디어 슬로프', location: '알프스 하우스 앞', streamUrl: 'https://www.elysian.co.kr'),
      SkiWebcam(name: '스키하우스 메인 광장', location: '전철역 연결 통로 앞', streamUrl: 'https://www.elysian.co.kr'),
    ],
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
      DetailedSlope(name: '실크로드 상단', section: '설천봉 (1,520m)', difficulty: SlopeDifficulty.novice, length: '3,100m', note: '구름 위를 달리는 환상의 롱코스'),
      DetailedSlope(name: '실크로드 하단', section: '설천봉 (1,520m)', difficulty: SlopeDifficulty.novice, length: '3,000m', note: '국내 단일 최장 슬로프 (총 6.1km)'),
      DetailedSlope(name: '루키힐', section: '만선베이스', difficulty: SlopeDifficulty.intermediate, length: '1,200m', note: '만선 최고의 인기 중급 카빙 코스'),
      DetailedSlope(name: '커넥션', section: '만선베이스', difficulty: SlopeDifficulty.beginner, length: '800m', note: '만선과 설천을 잇는 광폭 초급로'),
      DetailedSlope(name: '레이더스 상단', section: '만선봉 정상', difficulty: SlopeDifficulty.extreme, length: '950m', note: '국내 최고 경사도 38도 직벽 절벽 사면'),
      DetailedSlope(name: '레이더스 하단', section: '만선봉 정상', difficulty: SlopeDifficulty.expert, length: '800m', note: '레이더스 연결 고속 다운힐'),
      DetailedSlope(name: '프리폴', section: '설천 구역', difficulty: SlopeDifficulty.expert, length: '750m', note: '설천봉 급사면 상급 코스'),
      DetailedSlope(name: '야마가', section: '만선 구역', difficulty: SlopeDifficulty.expert, status: SlopeStatus.mogul, length: '850m', note: '전통의 모굴 테크니컬 코스'),
      DetailedSlope(name: '미뉴에트 / 모차르트', section: '설천봉 능선', difficulty: SlopeDifficulty.expert, length: '1,000m', note: '설천봉 능선 고난이도 코스'),
    ],
    availableTimeSlots: ['주간 (08:30~16:30)', '오후 (12:30~16:30)', '야간 (18:30~22:00)'],
    webcams: [
      SkiWebcam(name: '설천봉 정상 (해발 1,520m)', location: '향적봉 케이블카 상단', streamUrl: 'https://www.mdysresort.com'),
      SkiWebcam(name: '만선봉 정상 / 루키힐', location: '만선베이스 상단', streamUrl: 'https://www.mdysresort.com'),
      SkiWebcam(name: '설천하우스 광장', location: '실크로드 하단부', streamUrl: 'https://www.mdysresort.com'),
    ],
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
    webcams: [
      SkiWebcam(name: '알펜시아 메인 슬로프', location: '스키하우스 2층 전망대', streamUrl: 'https://www.alpensia.com'),
      SkiWebcam(name: '에코/델타 상급 정상', location: '리프트 최상단', streamUrl: 'https://www.alpensia.com'),
    ],
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
    webcams: [
      SkiWebcam(name: 'A / G 상급 슬로프', location: '마운틴 정상', streamUrl: 'https://www.oakvalley.co.kr'),
      SkiWebcam(name: '골프빌리지 베이스', location: '스키빌리지 중앙 광장', streamUrl: 'https://www.oakvalley.co.kr'),
    ],
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
      // 네트워크 오프라인 시 기본 더미 날씨 반환
    }

    return ResortWeather(
      temp: -3.2,
      apparentTemp: -6.5,
      windSpeed: 2.4,
      humidity: 55,
      weatherDesc: '맑음',
      iconEmoji: '☀️',
      dailyForecasts: ResortWeather._createDefault5DayForecasts(-3.2),
    );
  }
}

// -------------------------------------------------------------
// 초기 테스트용 타 유저 모집글
// -------------------------------------------------------------

List<RidePost> createInitialSamplePosts() {
  return [
    RidePost(
      id: 'test_post_1',
      title: '모나용평 옐로우/핑크에서 인터스키 패러렐 같이 연습해요!',
      content: '혼자 타기 심심해서 같이 슬로프 타실 분 구합니다. 기본기 위주로 부담 없이 재밌게 타요! 휴식 때 따뜻한 커피 한잔해요 ☕️',
      resortName: '모나용평 (평창)',
      slopes: ['옐로우 (초급)', '핑크 (초중급)'],
      discipline: '스키',
      style: '인터스키',
      skillLevel: '초급',
      purpose: '같이타요',
      dateText: '오늘',
      timeSlot: '야간 (19:00~22:00)',
      maxMembers: 2,
      currentMembers: 1,
      authorName: '평창눈사람',
      isJoined: false,
      isAuthor: false,
      chatMessages: [
        ChatMessage(
          sender: '시스템',
          text: '모나용평 슬로프 메이트 대화방이 개설되었습니다.\n참가자들과 상세 위치 및 복장(헬멧/자켓 색상)을 조율해보세요!',
          time: DateTime.now().subtract(const Duration(minutes: 45)),
          isSystem: true,
        ),
        ChatMessage(
          sender: '평창눈사람 (방장)',
          text: '안녕하세요! 오늘 야간에 핑크 리프트 앞에서 뵈어요. 저는 노란 자켓에 흰 헬멧 착용 중입니다~',
          time: DateTime.now().subtract(const Duration(minutes: 40)),
          isMe: false,
        ),
      ],
    ),
    RidePost(
      id: 'test_post_2',
      title: '곤지암 윈디/제타 상급 슬로프 라이딩 영상 팔로잉 품앗이!',
      content: '고프로 들고 탑니다. 윈디나 제타에서 서로 턴하는 모습 번갈아 가면서 찍어주실 분 계실까요? 안전 최우선으로 탑니다.',
      resortName: '곤지암리조트 (광주)',
      slopes: ['윈디 (중상급)', '제타 (상급)'],
      discipline: '보드',
      style: '테크니컬라이딩',
      skillLevel: '중급',
      purpose: '팔로잉',
      dateText: '내일',
      timeSlot: '심야 (22~02)',
      maxMembers: 1,
      currentMembers: 1,
      authorName: '곤지암라이더',
      isJoined: false,
      isAuthor: false,
      chatMessages: [
        ChatMessage(
          sender: '시스템',
          text: '곤지암리조트 슬로프 메이트 대화방이 개설되었습니다.\n참가자들과 상세 위치 및 복장(헬멧/자켓 색상)을 조율해보세요!',
          time: DateTime.now().subtract(const Duration(hours: 2)),
          isSystem: true,
        ),
        ChatMessage(
          sender: '곤지암라이더 (방장)',
          text: '고프로 액션캠 배터리 완충해뒀습니다! 참가하시면 베이스 카페 앞에서 인사 나누고 올라가요!',
          time: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
          isMe: false,
        ),
      ],
    ),
  ];
}

List<RidePost> gRidePosts = createInitialSamplePosts();

// -------------------------------------------------------------
// -------------------------------------------------------------
// 메인 화면 (4개 탭)
// -------------------------------------------------------------

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0; // 홈 탭 기본 활성화
  int _hubSubTabIndex = 0;
  StreamSubscription<List<RidePost>>? _postsSubscription;
  StreamSubscription<List<RideReview>>? _reviewsSubscription;

  @override
  void initState() {
    super.initState();
    // 🌐 실시간 모집글 스트림 구독
    _postsSubscription = AppFirebaseService.instance.streamRidePosts().listen((posts) {
      if (mounted && posts.isNotEmpty) {
        setState(() {
          gRidePosts = posts;
        });
      }
    });

    // 🌐 실시간 설질 후기 피드 스트림 구독
    _reviewsSubscription = AppFirebaseService.instance.streamReviews().listen((reviews) {
      if (mounted && reviews.isNotEmpty) {
        setState(() {
          gRideReviews = reviews;
        });
      }
    });
  }

  @override
  void dispose() {
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
            label: '같이 타요',
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
    final recentPosts = gRidePosts.where((post) {
      if (post.shouldHide) return false;
      if (gCurrentUser?.isUserBlocked(post.authorName) ?? false) {
        return false;
      }
      return true;
    }).take(4).toList();

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
                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.downhill_skiing_rounded, color: Color(0xFF2563EB), size: 20),
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
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.shade200, width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '접속 48명',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
          ),
        ],
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
              // 1. ⚡️ 초고속 4인 랜덤 매칭 실시간 현황 & 원터치 진입 카드
              // -------------------------------------------------------
              _buildRandomMatchingLiveCard(),

              const SizedBox(height: 26),

              // -------------------------------------------------------
              // 2. 🏂 실시간 같이 타요 최신 등록 항목들
              // -------------------------------------------------------
              _buildRecentPostsSection(recentPosts),

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade400.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300.withValues(alpha: 0.5), width: 1),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: Colors.amber, size: 16),
                    SizedBox(width: 4),
                    Text(
                      '실시간 4인 랜덤 매칭',
                      style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('대기열 작동중 🟢', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '지금 슬로프라면?\n조건 없이 4인 번개 매칭!',
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
            '복잡한 조건 없이 스키장 하나만 선택하면 4명이 모이는 즉시 채팅방이 열립니다.',
            style: TextStyle(fontSize: 12.5, color: Colors.blue.shade100, height: 1.35),
          ),
          const SizedBox(height: 16),

          // 실시간 스키장별 대기 현황 칩 (가로 스크롤)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildMatchingResortChip('비발디', '18명 대기', const Color(0xFF7C3AED)),
                _buildMatchingResortChip('휘닉스', '14명 대기', const Color(0xFF16A34A)),
                _buildMatchingResortChip('곤지암', '12명 대기', const Color(0xFF1E40AF)),
                _buildMatchingResortChip('지산', '11명 대기', const Color(0xFF16A34A)),
                _buildMatchingResortChip('모나용평', '9명 대기', const Color(0xFF0D9488)),
                _buildMatchingResortChip('하이원', '8명 대기', const Color(0xFF6B21A8)),
                _buildMatchingResortChip('웰리힐리', '7명 대기', const Color(0xFF0F766E)),
                _buildMatchingResortChip('엘리시안', '6명 대기', const Color(0xFF4B5563)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 매칭 시작 버튼
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                widget.onNavigateToTab(1, subTabIndex: 1); // 같이 타요 > 랜덤 매칭 탭으로 이동
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
                  Icon(Icons.shuffle_rounded, size: 20, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Text(
                    '4인 랜덤 매칭 시작하기 →',
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

  Widget _buildMatchingResortChip(String name, String count, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(count, style: const TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.w600)),
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
                  '실시간 같이 타요 모집 🏂',
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
                          weather != null ? '${weather.iconEmoji} ${weather.temp > 0 ? '+' : ''}${weather.temp.toStringAsFixed(1)}°' : '❄️ -2.5°',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
                        ),
                      ],
                    ),
                    Text(
                      weather != null ? '체감 ${weather.apparentTemp.toStringAsFixed(1)}° • ${weather.weatherDesc}' : '체감 -5.0° • 맑음',
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WriteRidePostScreen()),
              ).then((_) {
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
      length: 3,
      vsync: this,
      initialIndex: widget.initialSubTabIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant RideTogetherHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubTabIndex != widget.initialSubTabIndex) {
      _tabController.animateTo(widget.initialSubTabIndex.clamp(0, 2));
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
        title: const Text('같이 타요', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: const Color(0xFF2563EB),
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          tabs: const [
            Tab(text: '같이 타요'),
            Tab(text: '랜덤 매칭'),
            Tab(text: '같이 탔어요'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          RidePostListView(),
          RandomMatchingView(),
          RideReviewListView(),
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
  List<RidePost> get _myJoinedPosts =>
      gRidePosts.where((p) => p.canAccessChat).toList();

  void _showBlockUserDialog(String nickname) {
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
                  gCurrentUser!.blockUser(nickname);
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
                    trailing: const Icon(Icons.chevron_right),
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

  @override
  Widget build(BuildContext context) {
    final visiblePosts = gRidePosts.where((post) {
      if (post.shouldHide) return false;
      if (gCurrentUser?.isUserBlocked(post.authorName) ?? false) {
        return false;
      }
      return true;
    }).toList();

    final joinedCount = _myJoinedPosts.length;

    return Scaffold(
      body: visiblePosts.isEmpty
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
                      child: const Icon(Icons.snowboarding_rounded, size: 52, color: Color(0xFF2563EB)),
                    ),
                    const SizedBox(height: 16),
                    const Text('등록된 같이타요 모집글이 없습니다', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    const Text(
                      '내가 원하는 스키장과 시간대를 정해\n첫 번째 슬로프 메이트 모집글을 올려보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const WriteRidePostScreen()),
                        ).then((_) => setState(() {}));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('첫 메이트 모집글 작성하기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: visiblePosts.length,
              itemBuilder: (context, index) {
                final post = visiblePosts[index];
                return _buildPostCard(post);
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (joinedCount > 0) ...[
            Badge(
              label: Text('$joinedCount', style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.redAccent,
              child: FloatingActionButton(
                heroTag: 'floating_chat_button_hub',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF2563EB),
                elevation: 4,
                shape: const CircleBorder(side: BorderSide(color: Color(0xFF2563EB), width: 1.5)),
                onPressed: _openMyChatRoomsModal,
                tooltip: '참여 중인 대화방 바로가기',
                child: const Icon(Icons.mark_chat_unread_rounded, size: 26),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.extended(
            heroTag: 'floating_write_button_hub',
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WriteRidePostScreen()),
              );
              if (result == true) {
                setState(() {});
              }
            },
            icon: const Icon(Icons.edit),
            label: const Text('글쓰기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      post.resortName.split(' ')[0],
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${post.discipline}(${post.style}) • ${post.skillLevel}',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Spacer(),
                  if (post.isAuthor)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('내가 쓴 글', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                    )
                  else if (post.isJoined)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('참여 중', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.green)),
                    ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: post.isFull ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: post.isFull ? Colors.red.shade200 : Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person, size: 12, color: post.isFull ? Colors.red.shade700 : Colors.green.shade700),
                        const SizedBox(width: 2),
                        Text(
                          '${post.currentMembers}/${post.maxMembers + 1}명',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: post.isFull ? Colors.red.shade800 : Colors.green.shade800),
                        ),
                      ],
                    ),
                  ),
                  if (!post.isAuthor) ...[
                    const SizedBox(width: 2),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      itemBuilder: (context) => [
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
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(Icons.flag_outlined, size: 16, color: Colors.black87),
                              SizedBox(width: 8),
                              Text('모집글 신고하기', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (val) {
                        if (val == 'block') {
                          _showBlockUserDialog(post.authorName);
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
                                post.reportCount += 1;
                                post.reportedUserIds.add(currentUserId);
                                if (post.reportCount >= 3) {
                                  post.isBlinded = true;
                                }
                              });
                              if (post.id.isNotEmpty) {
                                AppFirebaseService.instance.reportRidePost(post.id, currentUserId);
                              }
                              if (post.isBlinded) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFFDC2626),
                                    content: Text('🚨 누적 신고 3회로 해당 모집글이 실시간 자동 블라인드(숨김) 처리되었습니다.'),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF1E3A8A),
                                    content: Text('🚨 신고가 접수되었습니다. (누적: ${post.reportCount}/3회)'),
                                  ),
                                );
                              }
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
                  Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    '${post.dateText} ${post.timeSlot}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '• ${post.authorName}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
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
  Timer? _matchProgressTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<String> _anonymousNames = [
    '익명의 라이더 A',
    '익명의 라이더 B',
    '익명의 라이더 C',
  ];

  final List<String> _currentQueue = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _matchProgressTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
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
                        '오늘의 랜덤 매칭 기회(1회)를 모두 사용하셨습니다.',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '무분별한 매칭 돌리기 방지와 진정성 있는 슬로프 만남을 위해 4인 랜덤 매칭은 1일 1회로 제한됩니다.\n\n매일 자정(00:00)에 다시 충전됩니다.',
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
                // 일반 같이타요 탭으로 전환
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

  void _startMatching() {
    if (gDailyRandomMatchRemaining <= 0) {
      _showDailyLimitExceededDialog();
      return;
    }

    setState(() {
      _isMatching = true;
      _matchedCount = 1;
      _elapsedSeconds = 0;
      _currentQueue.clear();
      _currentQueue.add('나 (참여자)');
    });

    // 1초마다 경과 시간 증가
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
      });
    });

    // 2번째 익명 라이더 합류 (1.6초 후)
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!_isMatching || !mounted) return;
      setState(() {
        _matchedCount = 2;
        _currentQueue.add(_anonymousNames[0]);
      });
    });

    // 3번째 익명 라이더 합류 (3.4초 후)
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (!_isMatching || !mounted) return;
      setState(() {
        _matchedCount = 3;
        _currentQueue.add(_anonymousNames[1]);
      });
    });

    // 4번째 익명 라이더 합류 및 매칭 성사 (5.2초 후)
    Future.delayed(const Duration(milliseconds: 5200), () {
      if (!_isMatching || !mounted) return;
      setState(() {
        _matchedCount = 4;
        _currentQueue.add(_anonymousNames[2]);
      });

      // 매칭 성공 축하 후 완전 익명 단체 채팅방 자동 입장
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!_isMatching || !mounted) return;
        _cancelMatching();
        _createAndEnterRandomChatRoom(_selectedResort);
      });
    });
  }

  void _cancelMatching() {
    _tickerTimer?.cancel();
    _matchProgressTimer?.cancel();
    if (mounted) {
      setState(() {
        _isMatching = false;
        _matchedCount = 1;
        _elapsedSeconds = 0;
        _currentQueue.clear();
      });
    }
  }

  void _createAndEnterRandomChatRoom(SkiResort resort) {
    // 1일 1회 매칭 기회 차감
    setState(() {
      gDailyRandomMatchRemaining = 0;
    });

    final now = DateTime.now();
    final newPost = RidePost(
      id: 'random_match_${now.millisecondsSinceEpoch}',
      title: '[⚡️ 4인 랜덤매칭] ${resort.shortName} 실시간 번개',
      content: '${resort.name}에서 모인 4인 실시간 슬로프 메이트 모임입니다. 슬로프에서 만나요!',
      resortName: resort.name,
      slopes: ['전체 슬로프 (자유)'],
      discipline: '스키/보드 혼합',
      style: '자유 라이딩',
      skillLevel: '무관',
      purpose: '랜덤 매칭',
      dateText: '오늘 실시간',
      timeSlot: '실시간 즉시',
      maxMembers: 3,
      currentMembers: 4,
      authorName: '나',
      isJoined: true,
      isAuthor: false,
      chatMessages: [
        ChatMessage(
          sender: '시스템',
          text: '🎉 [${resort.shortName}] 4인 슬로프 메이트가 매칭되었습니다!\n만날 위치(리프트 앞, 시계탑 등)와 복장(자켓 색상 등)을 편하게 조율해보세요 🎿🏂',
          time: now,
          isSystem: true,
        ),
        ChatMessage(
          sender: '익명의 라이더 A',
          text: '안녕하세요! 다들 반갑습니다 🙌 오늘 ${resort.shortName} 설질 진짜 좋네요!',
          time: now.add(const Duration(seconds: 1)),
          isMe: false,
        ),
        ChatMessage(
          sender: '익명의 라이더 B',
          text: '반가워요~ 저는 메인 베이스 스키하우스 앞인데 몇 시쯤 모일까요?',
          time: now.add(const Duration(seconds: 2)),
          isMe: false,
        ),
        ChatMessage(
          sender: '익명의 라이더 C',
          text: '오 좋아요! 저도 바로 합류할게요 ㅎㅎ 커피 한잔 들고 가겠습니다 ☕️',
          time: now.add(const Duration(seconds: 3)),
          isMe: false,
        ),
      ],
    );

    // 전체 글 목록 최상단에 추가
    gRidePosts.insert(0, newPost);

    // 🔔 4인 매칭 성공 로컬 푸시 알림 배너 띄우기
    NotificationService.instance.showLocalNotification(
      title: '⚡️ 4인 슬로프 번개 매칭 완료!',
      body: '[${resort.shortName}] 번개 동행 4인이 모두 모였습니다. 지금 대화방에서 만남 위치를 확인해보세요! ⛷️🏂',
      payload: newPost.id,
    );

    // 채팅방 화면으로 바로 이동
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(post: newPost),
      ),
    );
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
                          Text('초고속 4인 매칭', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasTicket ? Colors.green.shade600 : Colors.red.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        hasTicket ? '1일 1회 가능 🟢' : '오늘 기회 소진 🔴',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '조건 없이 딱 스키장만 정하고\n4명이 모이면 즉시 채팅 시작!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '무분별한 매칭 방지와 안전한 슬로프 만남을 위해 1일 1회만 제공됩니다.',
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
                            hasTicket ? '⚡️ 오늘 남은 매칭 기회: 1회' : '🔒 오늘 매칭 기회를 모두 사용했습니다',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasTicket ? Colors.blue.shade700 : Colors.red.shade600,
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
                      backgroundColor: hasTicket ? const Color(0xFF2563EB) : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: const Color(0xFF2563EB).withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shuffle_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          hasTicket
                              ? '[${_selectedResort.shortName}] 4인 랜덤 매칭 시작 (1/1회)'
                              : '오늘의 1회 매칭 완료됨 (내일 자정 초기화)',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                ? '🎉 4명 매칭 완료! 단체 채팅방을 개설합니다...'
                : '실시간 접속 중인 ${_selectedResort.shortName} 라이더를 찾는 중...',
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
              final isFilled = index < _matchedCount;
              final name = isFilled ? _currentQueue[index] : null;

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
                        isFilled ? name! : '대기열 탐색 중...',
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

  void _showBlockUserDialog(String nickname) {
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
                  gCurrentUser!.blockUser(nickname);
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
                  radius: 18,
                  backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  child: const Icon(Icons.person_outline_rounded, color: Color(0xFF2563EB), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            review.authorName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              review.resortName.split(' ')[0],
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(timeStr, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                // 설질 상태 뱃지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Text(
                    review.snowCondition,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  itemBuilder: (context) => [
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
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.flag_outlined, size: 16, color: Colors.black87),
                          SizedBox(width: 8),
                          Text('후기 신고하기', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'block') {
                      _showBlockUserDialog(review.authorName);
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

                          if (review.shouldHide) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Colors.red,
                                content: Text('🚨 누적 신고 3회로 해당 후기가 실시간 자동 블라인드(숨김) 처리되었습니다.'),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF1E3A8A),
                                content: Text('🚨 신고가 접수되었습니다. (누적: ${review.reportCount}/3회)'),
                              ),
                            );
                          }
                        },
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. 별점
            Row(
              children: List.generate(5, (starIdx) {
                return Icon(
                  starIdx < review.rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.amber,
                  size: 18,
                );
              }),
            ),
            const SizedBox(height: 10),

            // 3. 후기 본문 텍스트
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
                const SizedBox(width: 14),
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      '${review.commentCount}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
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
  String _selectedSnowCondition = '극상 파우더 ❄️';
  int _rating = 5;
  final TextEditingController _contentController = TextEditingController();
  final List<String> _attachedPhotos = [];
  final List<XFile> _selectedFiles = [];
  final List<String> _selectedTags = [];
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  final List<String> _snowConditions = [
    '극상 파우더 ❄️',
    '압설 최상 🎿',
    '약간 빙판 🧊',
    '슬러시 ☀️',
    '습설 🌨️',
  ];

  final List<String> _samplePhotoPresets = [
    '정상 슬로프 파우더 뷰 ❄️',
    '메이트들과 단체 인생샷 🏂',
    '야간 슬로프 조명 전경 🌙',
    '베이스 스키하우스 쉼터 ☕️',
    '슬로프 턴 엣지 자국 🎿',
  ];

  final List<String> _presetTags = [
    '#4인랜덤매칭후기',
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

              const Divider(height: 20),
              const Text('또는 추천 프리셋 선택', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _samplePhotoPresets.map((photo) {
                  final isAdded = _attachedPhotos.contains(photo);
                  return ActionChip(
                    avatar: Icon(Icons.add, size: 14, color: isAdded ? Colors.green : const Color(0xFF2563EB)),
                    label: Text(photo, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      if (!isAdded) {
                        setState(() {
                          _attachedPhotos.add(photo);
                        });
                      }
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitReview() async {
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
      snowCondition: _selectedSnowCondition,
      rating: _rating,
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

            // 2. 설질 상태 선택
            const Text('오늘의 설질 환경', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _snowConditions.map((cond) {
                final isSelected = _selectedSnowCondition == cond;
                return ChoiceChip(
                  label: Text(cond),
                  selected: isSelected,
                  selectedColor: const Color(0xFF2563EB),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedSnowCondition = cond);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 3. 만족도 별점
            const Text('라이딩 만족도', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (index) {
                final starVal = index + 1;
                return IconButton(
                  onPressed: () => setState(() => _rating = starVal),
                  icon: Icon(
                    starVal <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 36,
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // 4. 슬로프 사진 첨부
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

  void _showWebcamPlayer(BuildContext context, SkiResort resort, SkiWebcam webcam) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                          SizedBox(width: 4),
                          Text('LIVE CCTV', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        webcam.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 실시간 웹캠 시뮬레이션 뷰어
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [const Color(0xFF0F172A), resort.themeColor.withValues(alpha: 0.35)],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_rounded, size: 48, color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(height: 8),
                            Text(
                              '${resort.shortName} ${webcam.name}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              webcam.location,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')} HD',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '💡 해당 슬로프의 실시간 인원 밀집도 및 설질 상태를 확인할 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: resort.themeColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${resort.name} 공식 고화질 스트림에 연결되었습니다.')),
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('리조트 공식 고화질 영상 보기', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                          const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
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
                          ),
                      ],
                    ),
                  ),
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

                  // 3. 실시간 슬로프 웹캠 (CCTV)
                  Row(
                    children: [
                      const Text('📹 실시간 슬로프 웹캠 (CCTV)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${resort.webcams.length}개 채널', style: TextStyle(fontSize: 12, color: resort.themeColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...resort.webcams.map((cam) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.videocam_rounded, color: Colors.red, size: 20),
                        ),
                        title: Text(cam.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                        subtitle: Text(cam.location, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                        trailing: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          ),
                          onPressed: () => _showWebcamPlayer(context, resort, cam),
                          child: const Text('실시간 보기', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }),
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

                  // 4. 실시간 슬로프 운용 현황판 & 구역별 세부 슬로프
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
        title: const Text('스키장 정보', style: TextStyle(fontWeight: FontWeight.bold)),
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
// 실시간 슬로프 현황판 위젯
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

    final openCount = slopes.where((s) => s.status == SlopeStatus.open).length;
    final mogulCount = slopes.where((s) => s.status == SlopeStatus.mogul).length;
    final parkCount = slopes.where((s) => s.status == SlopeStatus.park).length;
    final closedCount = slopes.where((s) => s.status == SlopeStatus.closed).length;

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
                const Text('⛷️ 실시간 슬로프 현황판', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('총 ${slopes.length}개', style: TextStyle(fontSize: 13, color: widget.resort.themeColor, fontWeight: FontWeight.bold)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  CircleAvatar(radius: 3, backgroundColor: Colors.green),
                  SizedBox(width: 4),
                  Text('26/27 실시간', style: TextStyle(fontSize: 10.5, color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 운용 상태 서머리 배지 바
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusPill('🟢 오픈', '$openCount', Colors.green.shade700),
              _buildDivider(),
              _buildStatusPill('🟡 모굴', '$mogulCount', Colors.orange.shade800),
              _buildDivider(),
              _buildStatusPill('❄️ 파크', '$parkCount', Colors.purple.shade700),
              _buildDivider(),
              _buildStatusPill('🔴 미운영', '$closedCount', Colors.red.shade700),
            ],
          ),
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
        const SizedBox(height: 10),

        // 깔끔한 슬로프 카드 목록
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
                border: Border.all(
                  color: slope.status == SlopeStatus.closed
                      ? Colors.grey.shade300
                      : (slope.status == SlopeStatus.mogul ? Colors.orange.shade200 : Colors.grey.shade200),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 난이도 배지
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                      const SizedBox(width: 8),
                      // 슬로프 이름
                      Expanded(
                        child: Text(
                          slope.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: slope.status == SlopeStatus.closed ? Colors.grey : Colors.black87,
                            decoration: slope.status == SlopeStatus.closed ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      // 실시간 운용 상태 태그
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: slope.status.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: slope.status.color.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(slope.status.icon, size: 12, color: slope.status.color),
                            const SizedBox(width: 4),
                            Text(
                              slope.status.label,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: slope.status.color),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
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
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatusPill(String title, String count, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 2),
        Text(count, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 20, color: Colors.grey.shade300);
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

  // 이미 사용 중인 닉네임 목록 (중복 체크용)
  final List<String> _takenNicknames = [
    '평창눈사람',
    '곤지암라이더',
    '익명의보더',
    '용평파우더',
    '비발디보더',
    '하이원질주',
    '설질마스터',
  ];

  // -------------------------------------------------------------
  // 닉네임 변경 및 중복 체크 다이얼로그
  // -------------------------------------------------------------
  void _showEditNicknameDialog() {
    final user = gCurrentUser;
    if (user == null) return;

    final controller = TextEditingController(text: user.nickname);
    bool isDuplicateChecked = false;
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
                              if (isDuplicateChecked) {
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
                            onPressed: () {
                              final input = controller.text.trim();
                              if (input.length < 2) {
                                setDialogState(() {
                                  isDuplicateChecked = true;
                                  isAvailable = false;
                                  statusMessage = '⚠️ 2글자 이상 입력해주세요.';
                                  statusColor = Colors.red.shade700;
                                });
                                return;
                              }

                              if (input == user.nickname) {
                                setDialogState(() {
                                  isDuplicateChecked = true;
                                  isAvailable = true;
                                  statusMessage = '✅ 현재 사용 중인 나의 닉네임입니다.';
                                  statusColor = Colors.green.shade700;
                                });
                                return;
                              }

                              if (_takenNicknames.contains(input)) {
                                setDialogState(() {
                                  isDuplicateChecked = true;
                                  isAvailable = false;
                                  statusMessage = '❌ 이미 사용 중인 닉네임입니다.';
                                  statusColor = Colors.red.shade700;
                                });
                              } else {
                                setDialogState(() {
                                  isDuplicateChecked = true;
                                  isAvailable = true;
                                  statusMessage = '✅ 사용 가능한 멋진 닉네임입니다!';
                                  statusColor = Colors.green.shade700;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('중복 확인', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                  onPressed: isAvailable
                      ? () {
                          final newName = controller.text.trim();
                          setState(() {
                            user.nickname = newName;
                          });
                          AppFirebaseService.instance.saveUserProfile(user);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF1E3A8A),
                              content: Text('익명 닉네임이 "$newName"으로 안전하게 변경되었습니다.'),
                            ),
                          );
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
                _buildPointEarnRow(emoji: '⚡️', title: '4인 랜덤 매칭 성공 & 동행', points: '+50P', desc: '초고속 4인 매칭 완료 시 적립'),
                _buildPointEarnRow(emoji: '🏂', title: '같이타요 모집글 동행 성사', points: '+50P', desc: '모집글 작성 또는 참가 완료 시'),
                _buildPointEarnRow(emoji: '📸', title: '슬로프 사진 & 설질 후기 등록', points: '+30P', desc: '같이 탔어요 피드에 생생한 후기 작성'),
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
                          '• 카카오, 네이버, Apple OAuth는 오직 안전한 본인 인증 및 어뷰징 방지 목적으로만 사용됩니다.\n'
                          '• 실명, 전화번호, 이메일은 다른 사용자 및 슬로프 메이트에게 절대 공개되지 않습니다.\n'
                          '• 모든 매칭 및 대화방은 익명 닉네임으로 안전하게 진행됩니다.\n'
                          '• 구글 로그인은 정책상 비허용 처리되어 있습니다.',
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
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  gCurrentUser = null;
                });
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ).then((_) {
                  if (mounted) setState(() {});
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
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

  @override
  Widget build(BuildContext context) {
    final user = gCurrentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('개인설정 & 활동기록', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: user == null
          ? _buildLoggedOutView()
          : SingleChildScrollView(
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

                  // 6. 🛠️ QA & 자체 테스트 도구 (Sandbox)
                  _buildSectionTitle('🛠️ 개발자 & 자체 테스트 도구 (Sandbox)'),
                  const SizedBox(height: 8),
                  _buildQASandboxCard(),

                  const SizedBox(height: 24),

                  // 7. 계정 관리
                  _buildSectionTitle('계정 관리'),
                  const SizedBox(height: 8),
                  _buildAccountCard(user),

                  const SizedBox(height: 30),
                  Center(
                    child: Text(
                      '같이타요 v1.0.0 • 26/27 시즌\n카카오 • 네이버 • Apple 공식 OAuth 연동',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
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
                  value: user.riderTitle,
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
              '카카오, 네이버, Apple 소셜 계정으로\n3초 만에 안전하게 시작해보세요.',
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
              // 프로필 아바타 + OAuth 뱃지
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    child: Icon(
                      user.preferredDiscipline == '스노보드'
                          ? Icons.snowboarding_rounded
                          : Icons.downhill_skiing_rounded,
                      color: const Color(0xFF2563EB),
                      size: 28,
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
                            : (user.provider == SocialAuthProvider.naver ? 'N' : ''),
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
                          color: user.provider == SocialAuthProvider.kakao ? const Color(0xFF854D0E) : (user.provider == SocialAuthProvider.naver ? const Color(0xFF15803D) : Colors.black87),
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
            title: const Text('4인 랜덤 매칭 성공 알림', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
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

  // -------------------------------------------------------------
  // 🛠️ QA / 자체 테스트 샌드박스 도구 위젯
  // -------------------------------------------------------------
  Widget _buildQASandboxCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.handyman_rounded, color: Color(0xFF38BDF8), size: 20),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '🛠️ QA & 자체 테스트 도구 (Sandbox)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('DEBUG', style: TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '목데이터를 비워 백지 상태에서 글을 써보거나, 여러 계정을 넘나들며 혼자서도 2인 이상의 실시간 동행/참가/채팅 시뮬레이션을 완벽하게 테스트할 수 있습니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 14),

          // 도구 1: 목데이터 비우기 (클린 백지 모드) & 복원
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0xFFF87171)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    setState(() {
                      gRidePosts.clear();
                      gRideReviews.clear();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF991B1B),
                        content: Text('🧹 모든 샘플 글/후기를 비웠습니다. (백지 클린 모드) 직접 첫 글을 작성해보세요!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text('목데이터 비우기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    setState(() {
                      gRidePosts = createInitialSamplePosts();
                      gRideReviews = [
                        RideReview(
                          id: 'rev_1',
                          authorName: '익명의라이더#8192',
                          resortName: '모나용평 (평창)',
                          snowCondition: '극상 파우더 ❄️',
                          rating: 5,
                          content: '오늘 4인 랜덤매칭으로 만난 메이트분들과 메가그린이랑 레드 탔는데 설질 진짜 미쳤습니다 ㅠㅠ 다들 친절하셔서 인생샷도 찍어주시고 꿀잼이었어요! 다음 주에 또 봬요 🙌',
                          photoLabels: ['용평 레드 정상 파우더 뷰 ❄️', '4인 메이트 슬로프 단체샷 🏂'],
                          tags: ['#4인랜덤매칭후기', '#용평레드', '#설질대박', '#오후라이딩'],
                          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
                          likeCount: 24,
                          commentCount: 5,
                        ),
                        RideReview(
                          id: 'rev_2',
                          authorName: '익명의라이더#4120',
                          resortName: '비발디파크 (홍천)',
                          snowCondition: '야간 압설 굿 🎿',
                          rating: 5,
                          content: '퇴근하고 비발디 야간 땡보딩 왔습니다! 테크노 슬로프 사람도 많이 없고 엣지 촥촥 박히네요 ㅎㅎ 같이타요 모집글 보고 합류했는데 시간 가는 줄 몰랐네요.',
                          photoLabels: ['비발디 테크노 야간 조명 🌙', '베이스 스키하우스 앞 ☕️'],
                          tags: ['#비발디야간', '#테크노', '#퇴근보딩', '#메이트모임'],
                          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
                          likeCount: 18,
                          commentCount: 3,
                        ),
                      ];
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(0xFF065F46),
                        content: Text('📦 샘플 테스트 데이터가 정상 복원되었습니다.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('샘플 데이터 복원', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 도구 2: 계정 즉시 전환 (방장 ↔ 참가자 1인 멀티플레이어 시뮬레이션)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showSwitchAccountDialog,
              icon: const Icon(Icons.switch_account_rounded, size: 18),
              label: Text(
                '🎭 계정 즉시 전환 (현재: ${gCurrentUser?.nickname ?? "로그아웃"})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSwitchAccountDialog() {
    final accounts = [
      UserProfile(
        id: 'user_pyeongchang_1',
        provider: SocialAuthProvider.kakao,
        email: 'pyeongchang@kakao.com',
        nickname: '평창눈사람',
        preferredDiscipline: '스키',
        homeResort: '모나용평',
        level: '중급',
        joinedAt: DateTime(2026, 1, 1),
        riderTitle: '골드 라이더 🏂',
      ),
      UserProfile(
        id: 'user_gonjiam_2',
        provider: SocialAuthProvider.apple,
        email: 'gonjiam@apple.com',
        nickname: '곤지암라이더',
        preferredDiscipline: '스노보드',
        homeResort: '곤지암리조트',
        level: '상급',
        joinedAt: DateTime(2026, 1, 10),
        riderTitle: '플래티넘 마스터 ⛷️',
      ),
      UserProfile(
        id: 'user_vivaldi_3',
        provider: SocialAuthProvider.naver,
        email: 'vivaldi@naver.com',
        nickname: '비발디보더',
        preferredDiscipline: '스노보드',
        homeResort: '비발디파크',
        level: '초중급',
        joinedAt: DateTime(2026, 2, 1),
        riderTitle: '실버 라이더 🏂',
      ),
      UserProfile(
        id: 'user_new_4',
        provider: SocialAuthProvider.kakao,
        email: 'newbie@kakao.com',
        nickname: '익명의새내기#1234',
        preferredDiscipline: '스노보드',
        homeResort: '하이원리조트',
        level: '초급',
        joinedAt: DateTime.now(),
        riderTitle: '새싹 라이더 🌱',
      ),
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.switch_account_rounded, color: Color(0xFF2563EB), size: 22),
              SizedBox(width: 8),
              Text('테스트 계정 전환', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '계정을 전환하여 내가 올린 글에 다른 사람인 척 참가 신청하거나 1:1 대화방 채팅을 테스트할 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.35),
                ),
                const SizedBox(height: 12),
                ...accounts.map((acc) {
                  final isCurrent = gCurrentUser?.nickname == acc.nickname;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: isCurrent ? const Color(0xFFEFF6FF) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? const Color(0xFF2563EB) : Colors.grey.shade200,
                        width: isCurrent ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: acc.providerColor,
                        radius: 14,
                        child: Text(
                          acc.provider == SocialAuthProvider.kakao ? 'K' : (acc.provider == SocialAuthProvider.naver ? 'N' : ''),
                          style: TextStyle(color: acc.providerTextColor, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(acc.nickname, style: TextStyle(fontWeight: FontWeight.bold, color: isCurrent ? const Color(0xFF2563EB) : Colors.black87)),
                      subtitle: Text('${acc.homeResort} • ${acc.preferredDiscipline} • ${acc.level}', style: const TextStyle(fontSize: 11)),
                      trailing: isCurrent ? const Icon(Icons.check_circle, color: Color(0xFF2563EB), size: 18) : null,
                      onTap: () {
                        setState(() {
                          gCurrentUser = acc;
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF1E3A8A),
                            content: Text('\'${acc.nickname}\' 계정으로 즉시 전환되었습니다.'),
                          ),
                        );
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
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
            leading: const Icon(Icons.logout_rounded, color: Colors.red),
            title: const Text('로그아웃', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.red)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// OAuth 소셜 로그인 화면 (카카오 • 네이버 • 애플 3종 전용)
// -------------------------------------------------------------
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _handleSocialLogin(BuildContext context, SocialAuthProvider provider) async {
    UserProfile? profile;
    if (provider == SocialAuthProvider.kakao) {
      profile = await AppFirebaseService.instance.signInWithKakao();
    } else if (provider == SocialAuthProvider.apple) {
      profile = await AppFirebaseService.instance.signInWithApple();
    } else {
      profile = await AppFirebaseService.instance.signInWithNaver();
    }

    if (context.mounted && profile != null) {
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
                '국내 12개 스키장 4인 실시간 랜덤 매칭\n& 슬로프 메이트 커뮤니티',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade100,
                  height: 1.45,
                ),
              ),

              const Spacer(),

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

              // 2. 네이버 로그인 버튼 (#03C75A)
              _buildSocialButton(
                context: context,
                provider: SocialAuthProvider.naver,
                title: '네이버로 시작하기',
                bgColor: const Color(0xFF03C75A),
                textColor: Colors.white,
                iconWidget: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text(
                      'N',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 3. Apple 로그인 버튼 (Black)
              _buildSocialButton(
                context: context,
                provider: SocialAuthProvider.apple,
                title: 'Apple로 계속하기',
                bgColor: Colors.white,
                textColor: Colors.black,
                iconWidget: const Icon(Icons.apple_rounded, color: Colors.black, size: 24),
              ),

              const SizedBox(height: 24),

              // 보안 & 100% 익명성 안내
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '100% 익명 보장: 실명/연락처는 타인에게 공개되지 않습니다.',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade100),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
  void _joinRide() {
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
    final myNickname = gCurrentUser?.nickname ?? '익명의 라이더';
    setState(() {
      widget.post.isJoined = true;
      widget.post.currentMembers += 1;
      if (!widget.post.participantNames.contains(myNickname)) {
        widget.post.participantNames.add(myNickname);
      }
      widget.post.chatMessages.add(
        ChatMessage(
          sender: '시스템',
          text: '새로운 슬로프 메이트가 대화방에 참여했습니다! 👋\n만남 장소와 착용 복장을 조율해보세요.',
          time: DateTime.now(),
          isSystem: true,
        ),
      );
    });

    // 🚀 Firestore 실시간 참여 동기화
    if (widget.post.id.isNotEmpty) {
      AppFirebaseService.instance.toggleJoinRidePost(widget.post.id, myNickname);
    }

    // 🔔 방장에게 동행 참가 푸시 알림 전송
    NotificationService.instance.notifyRider(
      targetAuthorName: widget.post.authorName,
      title: '🎉 [${widget.post.resortName.split(' ')[0]}] 동행 참가 알림',
      body: '\'$myNickname\' 님이 \'${widget.post.title}\' 모임에 참가했습니다!',
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
                gCurrentUser!.blockUser(widget.post.authorName);
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
          if (!post.isAuthor)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onSelected: (val) {
                if (val == 'block') {
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

                      if (post.shouldHide) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('🚨 누적 신고 3회로 해당 모집글이 실시간 자동 블라인드(숨김) 처리되었습니다.'),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF1E3A8A),
                            content: Text('🚨 모집글 신고가 접수되었습니다. (누적: ${post.reportCount}/3회)'),
                          ),
                        );
                      }
                    },
                  );
                }
              },
              itemBuilder: (context) => [
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
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag_outlined, size: 16, color: Colors.black87),
                      SizedBox(width: 8),
                      Text('게시글 신고하기', style: TextStyle(fontSize: 13)),
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
                    Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
          child: canEnterChat
              ? FilledButton.icon(
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
                  label: const Text('참가자 전용 대화방 열기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

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

    final myNickname = gCurrentUser?.nickname ?? '익명의 라이더';
    final newMsg = ChatMessage(
      sender: myNickname,
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

    // 🔔 대화방 참가자 푸시 알림 전송
    NotificationService.instance.notifyRider(
      targetAuthorName: widget.post.authorName,
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

  void _showBlockParticipantModal() {
    final myNickname = gCurrentUser?.nickname ?? '';
    final otherParticipants = widget.post.participantNames.where((n) => n != myNickname).toList();

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
              const Text('차단 시 해당 사용자의 글과 후기가 숨김 처리되며, 향후 참가 시 알림이 제공됩니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                      final name = otherParticipants[index];
                      final isBlocked = gCurrentUser?.isUserBlocked(name) ?? false;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          child: const Icon(Icons.person, color: Color(0xFF2563EB), size: 18),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        trailing: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              if (isBlocked) {
                                gCurrentUser?.unblockUser(name);
                              } else {
                                gCurrentUser?.blockUser(name);
                              }
                              if (gCurrentUser != null) {
                                AppFirebaseService.instance.saveUserProfile(gCurrentUser!);
                              }
                            });
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF1E3A8A),
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

  @override
  Widget build(BuildContext context) {
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
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('대화방에서 퇴장했습니다.')),
                );
              }
            },
            itemBuilder: (context) => [
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
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF2563EB).withValues(alpha: 0.08),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
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
            child: StreamBuilder<List<ChatMessage>>(
              stream: widget.post.id.isNotEmpty
                  ? AppFirebaseService.instance.streamChatMessages(widget.post.id)
                  : const Stream.empty(),
              builder: (context, snapshot) {
                final displayMessages = (snapshot.hasData && snapshot.data!.isNotEmpty)
                    ? snapshot.data!
                    : widget.post.chatMessages;

                return ListView.builder(
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

                    return Align(
                      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: msg.isMe ? const Color(0xFF2563EB) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!msg.isMe) ...[
                              Text(msg.sender, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 2),
                            ],
                            Text(
                              msg.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: msg.isMe ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
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
      ),
    );
  }
}

// -------------------------------------------------------------
// 글쓰기 화면
// -------------------------------------------------------------

class WriteRidePostScreen extends StatefulWidget {
  const WriteRidePostScreen({super.key});

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

    final author = gCurrentUser?.nickname ?? '나 (방장)';
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
      isAuthor: true,
      isJoined: true,
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
        title: const Text('같이 타요 글쓰기'),
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
