import 'package:flutter/material.dart';
import 'package:pillchecker/screens/home/home_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
return MaterialApp(
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