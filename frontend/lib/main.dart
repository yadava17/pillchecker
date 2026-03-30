import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:pillchecker/app/app.dart';
import 'package:pillchecker/backend/database/app_database.dart';
import 'package:pillchecker/services/notification_service.dart';
import 'package:rive/rive.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RiveNative.init();

  if (kDebugMode) {
    try {
      final path = await AppDatabase.instance.debugDbPath();
      debugPrint('PillChecker DB path: $path');
      final diag = await AppDatabase.instance.runDiagnostics();
      debugPrint('DB diagnostics: $diag');
    } catch (e) {
      debugPrint('DB debug init: $e');
    }
  }

  runApp(const App());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initNotificationsSafe());
  });
}

Future<void> _initNotificationsSafe() async {
  try {
    await NotificationService.init().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }
}
