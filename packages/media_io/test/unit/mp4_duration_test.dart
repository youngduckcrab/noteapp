// MP4 / fragmented MP4 timeline length (m5-7/06-pdf 6.6.4; 8.2 T32a — review S-7): mvhd, then
// mvex/mehd, then the trun sample sums (tfhd / trex defaults), a cut last moof. The cases are in
// test/support/mp4_duration_cases.dart (Chrome runs them too — web/pure_logic_browser_test).
import '../support/mp4_duration_cases.dart';

void main() {
  mp4DurationCases();
}
