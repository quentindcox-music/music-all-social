import 'package:flutter/material.dart';
import 'package:music_all_app/screens/tabs_shell.dart';

import 'auth/auth_gate.dart';
import 'screens/sign_in_page.dart';


class MusicAllApp extends StatelessWidget {
  const MusicAllApp({super.key});

  @override
  Widget build(BuildContext context) {
return MaterialApp(
  debugShowCheckedModeBanner: false,
  title: 'Music All',
  theme: ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  ),
  home: AuthGate(
    signedOutBuilder: (_) => const SignInPage(),
    signedInBuilder: (_) => const TabsShell(),
  ),
);
  }
}
