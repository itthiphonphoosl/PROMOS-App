import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'services/auth_storage.dart';
import 'services/app_nav.dart';

void main() {
  runApp(const ProviderScope(child: PromosApp()));
}

class PromosApp extends StatelessWidget {
  const PromosApp({super.key});

  Future<Widget> _boot() async {
    final token = await AuthStorage.getToken();
    if (token == null) return const LoginPage();
    final expired = await AuthStorage.isTokenExpired();
    if (expired) return const LoginPage();
    return const HomePage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _boot(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return MaterialApp(
          navigatorKey: rootNavKey,
          debugShowCheckedModeBanner: false,
          title: 'ProMoSystem',
          theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            useMaterial3: true,
            cardTheme: const CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 2,
              shadowColor: Colors.black26,
            ),
          ),
          home: snap.data!,
        );
      },
    );
  }
}
