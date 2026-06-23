import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:averias_app/widgets/desktop_shell_scope.dart';

void main() {
  testWidgets('of() returns isDesktop true when set', (tester) async {
    late bool captured;
    await tester.pumpWidget(
      DesktopShellScope(
        isDesktop: true,
        child: Builder(builder: (ctx) {
          captured = DesktopShellScope.of(ctx)!.isDesktop;
          return const SizedBox();
        }),
      ),
    );
    expect(captured, isTrue);
  });

  testWidgets('of() returns isDesktop false when set', (tester) async {
    late bool captured;
    await tester.pumpWidget(
      DesktopShellScope(
        isDesktop: false,
        child: Builder(builder: (ctx) {
          captured = DesktopShellScope.of(ctx)!.isDesktop;
          return const SizedBox();
        }),
      ),
    );
    expect(captured, isFalse);
  });

  testWidgets('of() returns null when not in tree', (tester) async {
    late DesktopShellScope? captured;
    await tester.pumpWidget(
      Builder(builder: (ctx) {
        captured = DesktopShellScope.of(ctx);
        return const SizedBox();
      }),
    );
    expect(captured, isNull);
  });
}
