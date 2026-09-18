import 'package:integration_test/integration_test.dart';

import 'navigation_restoration_test.dart' as navigation_restoration;
import 'stage2_navigation_test.dart' as stage2_navigation;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  navigation_restoration.registerNavigationRestorationTests();
  stage2_navigation.registerStage2NavigationTests();
}
