import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:promos_app/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const PromosApp());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
