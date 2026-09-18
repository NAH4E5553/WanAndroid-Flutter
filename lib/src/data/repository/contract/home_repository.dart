import 'package:wanandroid_flutter/src/model/home_feed.dart';

abstract interface class HomeRepository {
  Future<HomeFeed> loadHome();
}
