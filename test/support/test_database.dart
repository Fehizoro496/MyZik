import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/app_database.dart';

/// An empty in-memory database of its own for one test. SQLite does real
/// I/O, which the fake clock of widget tests never completes: pass the
/// [tester] there so the database opens outside of it.
Future<AppDatabase> testDatabase([WidgetTester? tester]) async {
  if (tester == null) return AppDatabase.inMemory();
  return (await tester.runAsync(AppDatabase.inMemory))!;
}
