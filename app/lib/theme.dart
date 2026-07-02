import 'package:flutter/material.dart';

/// Identidad corporativa Grupo Cocamatic.
/// Colores: Naranja Pantone 1235 C (#F6B734) + Gris Pantone Cool Gray 8 C (#808080).
/// Tipografía: Carlito (sustituto libre, métricamente compatible con Calibri).
const Color kBrandOrange = Color(0xFFF6B734);
const Color kBrandGray = Color(0xFF808080);

/// Texto/iconos sobre naranja: casi negro (blanco no pasa contraste sobre #F6B734).
const Color kOnBrandOrange = Color(0xFF1A1A1A);

ThemeData cocamaticTheme() {
  const surface = Colors.white;
  const onSurface = kOnBrandOrange;
  // Gris muy claro (familia del gris corporativo) para rellenos/bordes sutiles.
  final surfaceLow = Colors.grey.shade100;

  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandOrange,
    brightness: Brightness.light,
  ).copyWith(
    primary: kBrandOrange,
    onPrimary: kOnBrandOrange,
    secondary: kBrandGray,
    onSecondary: Colors.white,
    // Sin crema: superficies en blanco, sin tinte naranja.
    surface: surface,
    onSurface: onSurface,
    surfaceContainerLowest: surface,
    surfaceContainerLow: surface,
    surfaceContainer: surfaceLow,
    surfaceContainerHigh: surfaceLow,
    surfaceContainerHighest: surfaceLow,
    surfaceBright: surface,
    surfaceDim: surface,
    surfaceTint: kBrandGray,
    outline: kBrandGray,
    outlineVariant: const Color(0xFFD9D9D9),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Carlito',
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBrandOrange,
      foregroundColor: kOnBrandOrange,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: kOnBrandOrange,
      indicatorColor: kOnBrandOrange,
    ),
  );
}
