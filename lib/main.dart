import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pillchecker/app/app.dart';
import 'package:pillchecker/services/notification_service.dart';
import 'package:rive/rive.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RiveNative.init();

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
