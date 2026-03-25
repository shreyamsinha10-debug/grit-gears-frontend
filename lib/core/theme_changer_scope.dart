// ---------------------------------------------------------------------------
// Theme changer scope – provides setThemeDark to descendants (e.g. LoginScreen).
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

class ThemeChangerScope extends InheritedWidget {
  const ThemeChangerScope({
    super.key,
    required this.setThemeDark,
    required super.child,
  });

  final void Function(bool dark) setThemeDark;

  static ThemeChangerScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeChangerScope>();
  }

  @override
  bool updateShouldNotify(ThemeChangerScope oldWidget) {
    return setThemeDark != oldWidget.setThemeDark;
  }
}
