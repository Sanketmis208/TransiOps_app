import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transi_ops_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login screen exposes operations and driver entry points', (
    tester,
  ) async {
    await const FlutterSecureStorage().deleteAll();
    SharedPreferences.setMockInitialValues({});
    await app.main();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Run your fleet from anywhere.'), findsOneWidget);
    expect(find.text('Operations'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Work email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();
    expect(find.text('DRIVER ACCESS'), findsOneWidget);
    expect(find.text('Start your assigned journey.'), findsOneWidget);
    expect(
      find.text(
        'Use the driver credentials issued by your company. Location never starts until you explicitly consent.',
      ),
      findsOneWidget,
    );
  });
}
