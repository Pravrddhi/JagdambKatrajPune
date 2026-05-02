import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:jagdhambtrustpune/main.dart';
import 'package:jagdhambtrustpune/providers/feature_flags_provider.dart';
import 'package:jagdhambtrustpune/providers/notification_provider.dart';
import 'package:jagdhambtrustpune/screens/splash_screen.dart';

void main() {
  testWidgets('App boots to splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => FeatureFlagsProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ],
        child: const MyApp(),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);

    // Advance fake time so splash timer completes and no pending timer remains.
    await tester.pump(const Duration(milliseconds: 7000));
  });
}
