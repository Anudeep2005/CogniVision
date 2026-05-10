import 'package:flutter/material.dart';

ThemeData themeData = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF1F5C45), // Deep Emerald Green
    secondary: Color(0xFFC8A96B), // Luxury Gold
    surface: Color(0xFFF5F7F2), // Soft Ivory Green
    onSurface: Color(0xFF214D3B), // Deep Forest Green
    surfaceContainer: Color(0xFFEAF5EE), // Soft Mint
  ),
  scaffoldBackgroundColor: const Color(0xFFF5F7F2),
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      color: Color(0xFF214D3B),
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5,
    ),
    bodyMedium: TextStyle(
      color: Color(0xFF355847),
    ),
  ),
);