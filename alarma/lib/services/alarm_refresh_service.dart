import 'package:flutter/foundation.dart';

class AlarmRefreshService {
  AlarmRefreshService._();
  static final AlarmRefreshService instance = AlarmRefreshService._();

  final ValueNotifier<int> refreshTick = ValueNotifier<int>(0);

  void notifyRefresh() {
    refreshTick.value++;
  }
}
