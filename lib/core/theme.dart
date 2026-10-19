import 'package:flutter/material.dart';

const kGreen = Color(0xFF0B6B57);
const kGold = Color(0xFFF2A71B);
const kInk = Color(0xFF10211C);
const kBg = Color(0xFFF4F6F4);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kGreen).copyWith(
    primary: kGreen,
    secondary: kGold,
    onSecondary: kInk,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kGreen,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDDE5E1)),
      ),
    ),
  );
}
