import 'package:flutter/widgets.dart';

class DesktopShellScope extends InheritedWidget {
  final bool isDesktop;

  const DesktopShellScope({
    super.key,
    required this.isDesktop,
    required super.child,
  });

  static DesktopShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopShellScope>();

  @override
  bool updateShouldNotify(DesktopShellScope old) => old.isDesktop != isDesktop;
}
