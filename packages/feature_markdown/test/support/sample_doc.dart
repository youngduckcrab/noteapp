// A rich sample MD 문서 for goldens and screenshots (Korean headings, nested lists, a task
// list, a table, code, math, a quote, an image placeholder, a footnote).
const String kSampleMarkdown = r'''# 회의록 — 2학기 프로젝트

이번 주 회의에서 정한 것을 **정리**했어요. 자세한 내용은 [계획 문서](https://example.com/plan)와 *아래 표*를 보세요. 인라인 코드 `flutter test`와 수식 $E = mc^2$ 도 들어 있어요.[^1]

## 할 일

- [x] 주제 정하기
- [ ] 자료 모으기
  - [ ] 논문 3편 읽기
  - [x] 설문 만들기
- [ ] 발표 준비

## 일정

1. 월요일: 역할 나누기
2. 수요일: 중간 점검
   - 진행률 확인
   - 어려운 점 나누기
     - 다음 회의에 가져오기
3. 금요일: ~~초안 제출~~ 다음 주로 미룸

| 이름 | 역할 | 진행률 |
|:-----|:----:|------:|
| 김민지 | 자료 조사 | 80% |
| 이서준 | 발표 자료 | 45% |
| 박하늘 | 코드 작성 | 60% |

> 좋은 질문은 답보다 오래 남는다.
> — 누군가

```dart
void main() {
  print('안녕, 마크다운!'); // 가로로 긴 줄은 옆으로 스크롤돼요 ------------------------------
}
```

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

![학교 지도](https://images.example.com/map.png)

---

[^1]: 각주도 이렇게 보여요.
''';
