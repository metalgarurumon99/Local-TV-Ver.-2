import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tv/main.dart';

void main() {
  testWidgets('App smoke test on desktop view', (WidgetTester tester) async {
    // Set desktop screen resolution
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const LocalTvApp());
    expect(find.byType(LocalTvApp), findsOneWidget);
    expect(find.text('LOCAL TV'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);
  });
}
