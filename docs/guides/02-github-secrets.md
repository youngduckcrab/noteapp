# 02. GitHub에 배포 키 등록하기

GitHub Actions가 Firebase Hosting에 앱을 올릴 수 있도록 '서비스 계정 키'를 만들어 GitHub 저장소에 등록해요. 등록하면 `main`에 올린 코드는 고정 주소(live)로, 다른 브랜치는 미리보기 주소로 자동 배포돼요. `main`이 아직 없는 지금은 개발 브랜치(저장소의 기본 브랜치)도 미리보기 주소로 가요 — live 주소는 `main`이 생긴 뒤부터 채워져요.

- **소요 시간**: 약 15분
- **끝나면 Claude에게 알려줄 것**: 등록을 마쳤다는 것, 확인 방법에서 본 실행 요약의 '주소' 줄(또는 화면 스크린샷)

## 준비물

- [01. Firebase 프로젝트 만들기](01-firebase-project.md)에서 확인한 **프로젝트 ID**
- GitHub 저장소의 관리 권한(저장소 주인이면 있어요)
- 컴퓨터 브라우저 — 키 파일(JSON)을 내려받아 내용을 복사해야 해서 컴퓨터가 편해요

## 따라 하기

### 1단계 — Google Cloud 콘솔에서 프로젝트 고르기

Firebase 프로젝트는 Google Cloud 프로젝트이기도 해요. 서비스 계정은 Google Cloud 콘솔에서 만들어요.

1. <https://console.cloud.google.com> 을 열고 01과 같은 Google 계정으로 로그인해요.
2. 화면 위쪽의 프로젝트 선택 상자를 눌러 01에서 만든 프로젝트를 골라요.

### 2단계 — 서비스 계정 만들기

1. 왼쪽 메뉴 **IAM 및 관리자** → **서비스 계정**을 눌러요. 안 보이면 콘솔 위 검색창에 '서비스 계정'을 입력해요.
2. 위쪽 **+ 서비스 계정 만들기**를 눌러요.
3. 서비스 계정 이름에 `github-deploy`를 입력하고 **만들고 계속하기**를 눌러요.

### 3단계 — 역할 5개 주기

'역할 선택' 상자를 누르고 검색창에 역할 이름을 입력해 하나씩 추가해요(**+ 다른 역할 추가**로 줄을 늘려요).

| 역할 이름 | 역할 ID (검색에 써도 돼요) |
|---|---|
| Firebase Hosting 관리자 | `roles/firebasehosting.admin` |
| Firebase 인증 관리자 | `roles/firebaseauth.admin` |
| Cloud Run 뷰어 | `roles/run.viewer` |
| API 키 뷰어 | `roles/serviceusage.apiKeysViewer` |
| 서비스 사용량 소비자 | `roles/serviceusage.serviceUsageConsumer` |

5개를 모두 넣었으면 **계속** → **완료**를 눌러요.

M4(동기화)에서 Firestore·Storage 규칙도 배포하게 되면 역할을 더 추가해야 해요. 그때 이 안내서를 고쳐서 알려 드릴게요.

### 4단계 — 키(JSON 파일) 만들기

1. 서비스 계정 목록에서 `github-deploy`를 눌러요.
2. 위쪽 **키** 탭 → **키 추가** → **새 키 만들기**를 눌러요.
3. **JSON**을 고르고 **만들기**를 누르면 파일이 내려받아져요.

이 파일이 있으면 누구나 이 프로젝트에 배포할 수 있어요. 다른 곳에 올리거나 보내지 마세요.

### 5단계 — GitHub에 Secret 등록

1. GitHub 저장소 → 위쪽 **Settings** → 왼쪽 **Secrets and variables** → **Actions**를 눌러요.
2. **Secrets** 탭에서 **New repository secret**을 눌러요.
3. **Name**에 `FIREBASE_SERVICE_ACCOUNT`를 그대로 입력해요.
4. 내려받은 JSON 파일을 메모장(텍스트 편집기)으로 열어 `{`부터 `}`까지 **전부** 복사해 **Secret** 칸에 붙여 넣어요.
5. **Add secret**을 눌러요.

### 6단계 — GitHub에 Variable 등록

1. 같은 화면에서 **Variables** 탭을 눌러요.
2. **New repository variable**을 눌러요.
3. **Name**에 `FIREBASE_PROJECT_ID`, **Value**에 01의 프로젝트 ID를 입력하고 **Add variable**을 눌러요.

### 7단계 — 내려받은 JSON 파일 지우기

등록을 마쳤으면 컴퓨터의 JSON 파일을 지우고 휴지통도 비워요. 키가 다시 필요하면 4단계로 새로 만들면 돼요.

## 확인 방법

1. GitHub 저장소 → **Actions** → 왼쪽 **CI**를 눌러요.
2. 가장 최근 실행을 열고 오른쪽 위 **Re-run all jobs**(또는 **Re-run jobs**)를 눌러요. 실행이 하나도 없으면 오른쪽 **Run workflow** → **Run workflow**를 눌러요.
3. 실행이 녹색 체크로 끝나면 실행 화면의 **Summary**에서 '빌드 결과'를 봐요. 개발 브랜치에 코드를 올린 실행(과 그 다시 실행)은 그 푸시에서 바뀐 부분의 테스트만 돌려 보통 15분 안에 끝나요. **Run workflow**로 직접 돌린 실행은 모든 테스트를 돌려 약 30분 걸려요(1차 통합 뒤 실측). '시험 범위:' 줄에 어느 쪽이었는지 나와요.
4. **주소:** 줄에 `https://…web.app` 주소가 있으면 성공이에요. 그 주소를 Claude에게 보내 주세요.

## 문제 해결

| 증상 | 해결 |
|---|---|
| Summary에 '주소: Firebase 미설정 — docs/guides/02-github-secrets.md' | Secret 이름 `FIREBASE_SERVICE_ACCOUNT`와 Variable 이름 `FIREBASE_PROJECT_ID`의 철자를 확인해요. Secret은 **Secrets** 탭, 프로젝트 ID는 **Variables** 탭에 있어야 해요. |
| 키를 만들 때 '서비스 계정 키 생성이 사용 중지됨' 같은 오류 | 조직 정책(`iam.disableServiceAccountKeyCreation`)이 키 만들기를 막고 있어요. 회사·학교 계정에서 생겨요. 개인 Gmail 계정이면 보통 해당 없어요. 개인 계정으로 01부터 다시 하거나 Claude에게 알려 주세요. |
| 배포 단계가 'Permission denied to get service [firebasehosting.googleapis.com]'(`serviceusage.services.get`)로 실패 | 역할 **서비스 사용량 소비자**(`roles/serviceusage.serviceUsageConsumer`)가 빠졌어요. **IAM 및 관리자** → **IAM**에서 `github-deploy` 줄의 연필 아이콘 → **+ 다른 역할 추가**로 넣고, 몇 분 뒤 다시 실행해요. |
| 배포 단계(Deploy to Firebase Hosting)가 권한 오류(403, permission)로 실패 | 3단계의 역할 5개가 모두 들어갔는지 확인해요(**IAM 및 관리자** → **IAM**에서 `github-deploy` 줄). 역할을 고친 뒤 몇 분 기다렸다가 다시 실행해요. |
| 배포 단계가 'project not found'로 실패 | `FIREBASE_PROJECT_ID` 값이 프로젝트 이름이 아니라 **프로젝트 ID**인지 확인해요. |
| 실행이 빨간 X로 끝나요 | 실행 화면 왼쪽 목록에서 빨간 X가 붙은 잡(예: **Browser tests**)을 눌러, 실패한 단계 이름과 로그 마지막 몇 줄을 복사하거나 스크린샷을 보내 주세요. 앞 잡이 실패하면 뒤 잡(**Build and deploy web**)은 돌지 않아 '빌드 결과'가 보이지 않아요. |
| 화면이 안내서와 달라요 | 스크린샷을 보내 주세요. 안내서를 고쳐 드릴게요. |
