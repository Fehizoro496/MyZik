import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';

/// Shared SQLite connection. Production overrides this before building the
/// provider container; tests supply an in-memory [AppDatabase].
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'appDatabaseProvider must be overridden before runApp',
  );
});
