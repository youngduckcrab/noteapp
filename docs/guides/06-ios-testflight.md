# 06. iOS TestFlight (초안)

> **초안이에요.** 네이티브 앱으로 바꾸는 단계에서 Claude가 그때의 최신 화면을 기준으로 다시 고쳐요. 지금은 따라 하지 않아도 돼요.

iPad에 네이티브 앱을 TestFlight로 설치하는 준비예요. GitHub Actions의 macOS 실행 시간은 무료 사용량에서 10배로 계산돼서 이 작업은 손으로만 실행해요.

- **소요 시간**: 약 1시간 + Apple Developer Program 가입 승인 대기(하루 이상 걸릴 수 있어요)
- **끝나면 Claude에게 알려줄 것**: 가입이 끝났는지, Team ID, App Store Connect에 앱을 만들었는지, GitHub에 Secret 4개와 Variable 1개를 등록했는지

## 준비물

- Apple ID와 Apple Developer Program 가입(연회비가 있어요)
- 번들 ID — 앱을 구분하는 이름이에요. 한 번 정하면 바꾸기 어려워서 Claude와 먼저 정해요
- 컴퓨터 브라우저, iPad(TestFlight 앱 설치용)

## 따라 하기

### 1단계 — Apple Developer Program 가입

1. <https://developer.apple.com/programs/> 에서 **등록**(Enroll)을 눌러 개인으로 가입해요.
2. 승인 메일이 오면 <https://developer.apple.com/account> → **멤버십 세부 사항**에서 **팀 ID**(Team ID)를 확인해요.

### 2단계 — App Store Connect에 앱 만들기

1. <https://appstoreconnect.apple.com> → **앱** → **+** → **신규 앱**을 눌러요.
2. 플랫폼 **iOS**, 이름 `필기노트`, 기본 언어 **한국어**, 번들 ID(Claude와 정한 것), SKU(아무 영문·숫자, 예: `noteapp`)를 넣고 **생성**해요.

### 3단계 — API 키 만들기

1. App Store Connect → **사용자 및 액세스** → **통합** 탭 → **App Store Connect API** → **팀 키**를 눌러요.
2. **+**(키 생성)를 누르고 이름 `github`, 액세스 **App Manager**로 만들어요.
3. **키 ID**와 위쪽의 **Issuer ID**를 적어 두고, **API 키 다운로드**로 `.p8` 파일을 받아요. **이 파일은 한 번만 내려받을 수 있어요.**

### 4단계 — GitHub에 등록

GitHub 저장소 → **Settings** → **Secrets and variables** → **Actions**.

| 탭 | 이름 | 값 |
|---|---|---|
| Secrets | `APPLE_TEAM_ID` | 1단계의 팀 ID |
| Secrets | `ASC_KEY_ID` | 3단계의 키 ID |
| Secrets | `ASC_ISSUER_ID` | 3단계의 Issuer ID |
| Secrets | `ASC_PRIVATE_KEY` | `.p8` 파일을 메모장으로 열어 `-----BEGIN PRIVATE KEY-----`부터 `-----END PRIVATE KEY-----`까지 전부 |
| Variables | `IOS_TESTFLIGHT_ENABLED` | `true` |

등록한 뒤 `.p8` 파일은 안전한 곳에 보관하거나 지워요.

### 5단계 — 빌드 실행

1. 저장소 → **Actions** → 왼쪽 **iOS TestFlight** → **Run workflow**를 눌러요.
2. 확인 칸에 `yes`를 입력하고 **Run workflow**를 눌러요. 한 번에 무료 사용 시간을 약 150분(실행 15분 × 10배) 써요.

### 6단계 — iPad에 설치

1. iPad App Store에서 **TestFlight** 앱을 설치해요.
2. App Store Connect → 앱 → **TestFlight** 탭에서 빌드가 '테스트 가능'이 되면 내부 테스터에 자신을 추가해요.
3. 초대 메일이나 TestFlight 앱에서 필기노트를 설치해요.

## 확인 방법

- App Store Connect → 앱 → **TestFlight** 탭에 빌드 번호가 보이고 상태가 '처리 중'에서 '테스트 가능'으로 바뀌어요.
- iPad TestFlight 앱에 필기노트가 보이고, 설치해 열면 라이브러리 화면이 나와요.

## 문제 해결

| 증상 | 해결 |
|---|---|
| 실행했는데 작업이 건너뛰어졌어요(회색) | Variable `IOS_TESTFLIGHT_ENABLED`가 `true`인지, 확인 칸에 소문자 `yes`를 넣었는지 확인해요. |
| 서명(signing)·프로비저닝 오류 | 이 워크플로는 아직 검증 전 초안이에요. 실패한 단계의 로그를 Claude에게 보내 주세요. |
| `.p8` 파일을 잃어버렸어요 | 3단계 화면에서 그 키를 폐기하고 새 키를 만들어 4단계의 세 Secret을 다시 넣어요. |
| 화면이 안내서와 달라요 | 스크린샷을 보내 주세요. 안내서를 고쳐 드릴게요. |
