// lib/src/lab/lab_sentences.dart — (internal) the A-4 lab's 30 fixed
// sentences (m5-7/05-library 6.20): 10 Korean, 10 mixed Korean + English,
// 10 English. Not anybody's own notes — the user writes them by hand on the
// device and the lab compares what the engine reads.

/// The three groups of the lab's summary.
enum LabGroup { korean, mixed, english }

/// One sentence to write.
final class LabSentence {
  const LabSentence(this.group, this.text);

  final LabGroup group;
  final String text;
}

/// In the order the lab shows them.
const List<LabSentence> kLabSentences = [
  LabSentence(LabGroup.korean, '오늘 회의록을 정리했다'),
  LabSentence(LabGroup.korean, '미분 방정식의 일반해를 구한다'),
  LabSentence(LabGroup.korean, '다음 주 월요일까지 보고서 제출'),
  LabSentence(LabGroup.korean, '수업 시간에 배운 내용을 복습하자'),
  LabSentence(LabGroup.korean, '행렬의 고윳값을 계산한다'),
  LabSentence(LabGroup.korean, '점심은 학교 앞 식당에서 먹었다'),
  LabSentence(LabGroup.korean, '실험 결과를 표로 정리하기'),
  LabSentence(LabGroup.korean, '내일 아침 일찍 도서관에 간다'),
  LabSentence(LabGroup.korean, '확률 변수의 기댓값과 분산'),
  LabSentence(LabGroup.korean, '발표 자료에 그림을 추가한다'),
  LabSentence(LabGroup.mixed, '오늘 meeting 내용 정리'),
  LabSentence(LabGroup.mixed, 'Laplace 변환 복습하기'),
  LabSentence(LabGroup.mixed, 'API 키는 서버에 둔다'),
  LabSentence(LabGroup.mixed, 'Git 브랜치를 새로 만든다'),
  LabSentence(LabGroup.mixed, 'PDF 파일을 노트에 넣기'),
  LabSentence(LabGroup.mixed, 'Python 코드로 그래프 그리기'),
  LabSentence(LabGroup.mixed, 'Fourier 급수의 수렴 조건'),
  LabSentence(LabGroup.mixed, 'iPad로 필기한 내용 백업'),
  LabSentence(LabGroup.mixed, 'CPU 사용률이 90% 넘음'),
  LabSentence(LabGroup.mixed, 'Chapter 3 연습문제 풀기'),
  LabSentence(LabGroup.english, 'Quarterly review notes'),
  LabSentence(LabGroup.english, 'Read chapter three again'),
  LabSentence(LabGroup.english, 'Call the lab before noon'),
  LabSentence(LabGroup.english, 'Draft the project summary'),
  LabSentence(LabGroup.english, 'Linear algebra homework'),
  LabSentence(LabGroup.english, 'Meeting moved to Friday'),
  LabSentence(LabGroup.english, 'Check the sample results'),
  LabSentence(LabGroup.english, 'Buy milk and fresh bread'),
  LabSentence(LabGroup.english, 'Send the slides tonight'),
  LabSentence(LabGroup.english, 'Prepare for the final exam'),
];
