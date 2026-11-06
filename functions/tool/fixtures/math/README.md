# 수식 비교 도구 고정 자료 (07-sync 6.9.1)

`npm run eval:math`(도구 `tool/math_eval.ts`)가 이 폴더 아래의 `*.json`을 모두 읽는다(하위 폴더 포함, 경로 순).

## 형식

```json
{"id": "frac-01", "tags": ["fraction"], "expected": "\\frac{a+b}{c}",
 "strokes": {"x": [[312.4, 313.1]], "y": [[88.0, 88.6]], "t": [[0, 8]]},
 "png": "frac-01.png", "source": "synthetic", "locale": "ko"}
```

| 키 | 뜻 |
|---|---|
| `id` | 고정 자료 이름, 폴더 전체에서 하나 |
| `tags` | 분류(분수·지수·루트·적분·시그마·극한·행렬·그리스 문자·연립방정식 — PLAN F-14 범위) |
| `expected` | 정답 LaTeX(사용자가 입력) |
| `strokes` | 서버 함수 `recognizeMath` 입력과 같은 모양(계약 7.2.13, CP-L8): 페이지 pt 좌표, `t`는 첫 획 첫 점부터의 정수 ms |
| `png` | 같은 폴더의 PNG 파일 이름(선택 — PNG만 받는 엔진용) |
| `source` | `synthetic`(저장소에 커밋, 도구 자체 시험용) 또는 `user-<기기>-<날짜>` |
| `locale` | `ko`(기본) 또는 `en` — 엔진에 넘기는 언어 힌트 |

`strokes`와 `png` 중 하나는 있어야 한다. 엔진이 받지 않는 입력만 있는 행은 호출하지 않고 `unsupportedInput`으로 적는다.

## 사용자 손글씨 표본

- **수식만** 넣는다. 사용자가 동의한 뒤에만 넣는다(U18 기본값 '도형·수식만').
- 앱에서 이 형식으로 내보내는 개발자 기능은 LIBRARY 수식 패드의 고정 자료 모드다(05-library 6.14.7). 형식을 바꿀 때는 LIBRARY에 알린다.
- 실행 결과 폴더 `eval-out/`은 커밋하지 않는다.

## `synthetic/` — 도구 시험용 5개

가짜 엔진(`\frac{획 수}{점 수}`, PNG는 `\sqrt{바이트 수}`, 첫 점 (-1,-1)은 `upstream` 실패 — 계약 7.6)에 맞춰 정확 일치 2(`frac-01`·`sqrt-01`), 정규화 일치만 1(`frac-02` — `\dfrac`), 불일치 1(`pow-01`), 엔진 실패 1(`upstream-01`)이 나오게 만들었다. `tool/test/math_eval.test.ts`가 이 다섯으로 `summary.md` 전체를 고정 문자열과 비교한다.
