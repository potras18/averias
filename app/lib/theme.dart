import 'package:flutter/material.dart';

/// Identidad corporativa Grupo Cocamatic.
/// Colores: Naranja Pantone 1235 C (#F6B734) + Gris Pantone Cool Gray 8 C (#808080).
/// Tipografía: Carlito (sustituto libre, métricamente compatible con Calibri).
const Color kBrandOrange = Color(0xFFF6B734);
const Color kBrandGray = Color(0xFF808080);

/// Texto/iconos sobre naranja: casi negro (blanco no pasa contraste sobre #F6B734).
const Color kOnBrandOrange = Color(0xFF1A1A1A);

ThemeData cocamaticTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandOrange,
    brightness: Brightness.light,
  ).copyWith(
    primary: kBrandOrange,
    onPrimary: kOnBrandOrange,
    secondary: kBrandGray,
    onSecondary: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Carlito',
    appBarTheme: const AppBarTheme(
      backgroundColor: kBrandOrange,
      foregroundColor: kOnBrandOrange,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: kOnBrandOrange,
      indicatorColor: kOnBrandOrange,
    ),
  );
}
