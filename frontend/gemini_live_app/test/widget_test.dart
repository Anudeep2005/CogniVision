import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vision_aid_app/features/auth/login_screen.dart';

void main() {
  testWidgets('Login screen has essential UI elements', (WidgetTester tester) async {
    // Build the login screen
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // Verify presence of title
    expect(find.text('CogniVision'), findsOneWidget);
    
    // Verify presence of Sign In button
    expect(find.text('Sign In'), findsOneWidget);
    
    // Click on 'Create Account' to see role selection
    await tester.tap(find.text('New here? Create Account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('User'), findsOneWidget);
    expect(find.text('Guardian'), findsOneWidget);
  });
}
