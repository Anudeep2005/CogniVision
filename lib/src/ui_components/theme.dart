import 'package:flutter/material.dart';

ThemeData themeData = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color.fromARGB(255, 18, 69, 2),
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  ).copyWith(surface: const Color.fromARGB(255, 7, 41, 21)),
);