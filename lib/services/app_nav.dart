import 'package:flutter/material.dart';
import 'auth_storage.dart';
import '../pages/login_page.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

Future<void> forceToLogin() async {
  await AuthStorage.clearAll();

  final nav = rootNavKey.currentState;
  if (nav == null) return;

  nav.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (_) => false,
  );
}
