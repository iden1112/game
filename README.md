# 훈련장 1v1

배틀그라운드 훈련장 스타일의 1대1 FPS 웹게임입니다. HTML 파일 하나로 실행되며 PC(크롬) 전용입니다.

## 실행

### 웹사이트로 실행 (Node.js)

Node.js 18 이상이 필요합니다. 추가 패키지 설치는 필요 없습니다.

```
npm start
```

크롬에서 http://localhost:3000 을 엽니다. 포트를 바꾸려면 `PORT` 환경변수를 지정합니다. (PowerShell: `$env:PORT=8080; npm start`)

### 파일로 바로 실행

`훈련장 1v1.html` 파일을 크롬에서 열어도 됩니다. (three.js r128, PeerJS 내장)

## Godot 버전 (`godot/` 폴더)

같은 게임을 Godot 4.7로 옮긴 버전입니다. 웹에서 바로 하기: **https://training-1v1.onrender.com/godot/**

- `godot/` — Godot 프로젝트 (Godot 4.7에서 `godot/project.godot` 열기 → F5). 자세한 내용은 `godot/README.md`
- `web/godot/` — 웹으로 내보낸 결과 (사이트의 `/godot/` 에서 보여줌)
- 온라인 대전은 웹 게임의 「학교 와이파이용 방」(코드 R…)과 같은 방식이라 웹·Godot 이 같은 방에서 만날 수 있어요

다시 내보내기: Godot 에서 프로젝트 → 내보내기 → Web → 「프로젝트 내보내기」(경로 `../web/godot/index.html`), 또는

```
Godot_v4.7.2-stable_win64_console.exe --headless --path godot --export-release Web ../web/godot/index.html
```

## 새 버전 올리기

웹사이트: **https://training-1v1.onrender.com** (Render에서 `server.js` 실행)

파일로 받아서 연 게임은 시작할 때 `https://training-1v1.onrender.com/version.json`을 확인해서, 더 높은 버전이 있으면 시작 화면에 업데이트 알림을 띄웁니다. 웹사이트로 연 게임은 항상 최신이라 확인하지 않습니다.

1. `훈련장 1v1.html`에서 `GAME_BUILD` 숫자를 1 올립니다.
2. `version.json`의 `build`를 같은 숫자로 맞추고, `note`에 바뀐 내용을 짧게 적습니다.
3. 커밋하고 푸시합니다.

## 로그인 (Firebase)

시작 화면에서 구글 계정 또는 이메일/비밀번호로 로그인할 수 있습니다. 로그인은 선택 사항입니다.

- Firebase 프로젝트: `training-1v1` (Authentication → Google, 이메일/비밀번호 사용)
- 설정값은 게임 파일의 `FIREBASE_CONFIG`에 있습니다. (공개용 값)
- 새 주소에서 서비스하려면 Firebase 콘솔 → Authentication → 설정 → 승인된 도메인에 그 주소를 추가해야 구글 로그인이 됩니다.
- 게임을 파일로 열면 로그인 버튼이 보이지 않습니다. (웹사이트에서만 동작)

## 게임 모드

- **AI 대전** — 봇과 대결, 7점 선승. 봇 난이도·맵 선택
- **친구와 대전** — 방 코드로 온라인 대전 (1대1 · 2대2 · 3대3), 학교 와이파이용 중계 방 지원
- **훈련장** — 사격 연습, 기록 확인

## 주요 요소

- 1인칭/3인칭 전환, 둘러보기, 기울이기, 앉기·엎드리기, 점프·넘기
- 총 고르기(풀파츠 로드아웃), 단발/점사/연사 사격 모드
- 레드도트·홀로·2x~15x 조준경, 조준경 배율 조절, 숨 참기
- 수류탄(쿠킹·굴리기), 연막탄, 섬광탄
- 헬멧·조끼 방어구 레벨, 데미지 방향 표시, 킬피드, K/D 점수판
- 설정: 감도, 키 설정, 시야각, 그래픽 품질, 음량, 조준선 커스터마이즈

## 조작

| 키 | 동작 |
|---|---|
| W A S D | 이동 |
| Shift | 달리기 (조준 중 숨 참기) |
| Space | 점프 / 넘기 |
| C / Z | 앉기 / 엎드리기 |
| Q / E | 기울이기 |
| V | 1인칭 ↔ 3인칭 |
| Alt | 둘러보기 |
| 좌클릭 / 우클릭 | 사격 / 조준 |
| R | 재장전 |
| B | 사격 모드 |
| 1 2 | 무기 교체 |
| G / 5 | 수류탄 |
| Tab | 점수판 |
| ~ | 총 바꾸기 (라운드 시작 전) |
| Esc | 일시정지 |
