# eatSleepRide Release v1.1.0 (Build 14)

- **출시일**: 2026년 11월 9일
- **패키지 식별자**: `com.tlskals.eatsleepride`
- **버전**: `1.1.0+14`

---

## 📦 산출물 내역

1. **`eatSleepRide-v1.1.0+14-release.aab`** (66.0 MB)
   - 구글 플레이 콘솔 프로덕션 / 내부 테스트 배포용 Android App Bundle
   - R8 난독화 (`isMinifyEnabled = true`) 및 리소스 최적화 (`isShrinkResources = true`) 적용
2. **`eatSleepRide-v1.1.0+14-appstore.ipa`** (63.0 MB)
   - 애플 App Store Connect / TestFlight 배포용 iOS 바이너리
   - `CFBundleName: eatSleepRide` 적용
3. **`eatSleepRide-v1.1.0+14-release.apk`** (77.0 MB)
   - 안드로이드 실기기 직접 설치 및 QA 테스트용 릴리즈 APK
4. **`mapping.txt`** (26.0 MB)
   - 구글 플레이 콘솔 비정상 종료(Crash) 스택트레이스 복원용 R8 난독화 매핑 파일

---

## 🚀 주요 릴리즈 변경사항 (Changelog)

1. **전국 12개 스키장 슬로프 평균경사도 전수 적용**
   - 곤지암, 비발디, 용평, 휘닉스, 하이원 등 12개 스키장의 각 슬로프별 공식 평균 경사도(`slopeDegree`) 데이터 탑재
2. **무주 덕유산 리조트 슬로프맵 초고화질 복원**
   - `3743 x 2505` 고해상도 원본 교체, `FilterQuality.high` 및 6.0배 핀치 줌 적용 (픽셀 깨짐/풍화 원천 차단)
3. **초경량 60px 햅틱 당김 새로고침 (`CupertinoSliverRefreshControl`)**
   - 212px 이상 무겁게 당겨야 했던 기존 방식에서 살짝만 톡(60px) 당겨도 반응하는 반응형 스피너 및 `HapticFeedback.mediumImpact()` 적용
4. **iOS 시스템 인증 팝업 명칭 수정**
   - `CFBundleName`을 `project_t`에서 `eatSleepRide`로 수정하여 시스템 팝업 표기 완벽 일치
5. **무관용 / Zero-Tolerance 문구 전면 순화**
   - 친절하고 정중한 커뮤니티 클린 가이드라인 문구로 개편
6. **파이어베이스 DB 클린업**
   - 10/7 출시 이전 더미/네이버 테스트 계정 40개 전량 삭제 및 순수 활동 라이더 52명 데이터 정제

