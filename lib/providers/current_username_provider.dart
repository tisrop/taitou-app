import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_providers.dart';

/// 当前账号 username，作为账号级本地数据的隔离键。
final currentUsernameProvider = FutureProvider<String?>((ref) async {
  return ref.read(discourseServiceProvider).getUsername();
});
