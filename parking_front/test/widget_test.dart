// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:parking_front/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartParkApp());

    // Verify that the login screen is displayed
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('SmartPark'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
