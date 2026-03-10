import 'package:flutter/material.dart';
import 'package:pillchecker/screens/home/home_screen.dart';

final GlobalKey<NavigatorState> appNavKey = GlobalKey<NavigatorState>();

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavKey, // ✅ ADD THIS
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
      home: const HomeScreen(),
    );
  }
}
