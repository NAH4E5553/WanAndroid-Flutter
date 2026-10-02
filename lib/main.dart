import 'package:wanandroid_flutter/src/app/bootstrap/bootstrap.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';

void main() {
  StartupMetrics.instance.start();
  bootstrap();
}
