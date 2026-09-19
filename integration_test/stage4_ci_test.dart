import 'package:integration_test/integration_test.dart';

import 'navigation_restoration_test.dart' as navigation_restoration;
import 'reader_history_test.dart' as reader_history;
import 'stage2_navigation_test.dart' as stage2_navigation;
import 'topics_gestures_test.dart' as topics_gestures;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  navigation_restoration.registerNavigationRestorationTests();
  stage2_navigation.registerStage2NavigationTests();
  topics_gestures.registerTopicsGestureTests();
  reader_history.registerReaderHistoryTests();
}
