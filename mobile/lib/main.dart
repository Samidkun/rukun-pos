import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/cashier/presentation/cashier_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: RukunApp(),
    ),
  );
}

class RukunApp extends StatelessWidget {
  const RukunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rukun POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const CashierScreen(),
    );
  }
}
