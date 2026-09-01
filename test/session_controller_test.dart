import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transi_ops_app/core/api_client.dart';
import 'package:transi_ops_app/core/auth/driver_session_store.dart';
import 'package:transi_ops_app/core/session_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stores a mobile session returned by login', () async {
    final api = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"token":"mobile-token","user":{"id":"user-1","name":"Raven Kumar","email":"driver@transitops.in","role":"DRIVER","organizationId":"org-1","organizationName":"TransitOps","mustChangePassword":false}}',
          200,
        ),
      ),
    );
    final tokenStore = MemorySessionTokenStore();
    final session = SessionController(api, tokenStore: tokenStore);

    expect(
      await session.login(email: 'driver@transitops.in', password: 'password'),
      isTrue,
    );
    expect(api.token, 'mobile-token');
    expect(tokenStore.token, 'mobile-token');
    expect(
      (await SharedPreferences.getInstance()).getString('transitops_token'),
      isNull,
    );
    expect(session.user?.name, 'Raven Kumar');
  });

  test(
    'explains a missing mobile token instead of throwing a type cast',
    () async {
      final session = SessionController(
        ApiClient(
          httpClient: MockClient(
            (_) async => http.Response(
              '{"user":{"id":"user-1","name":"Raven Kumar","email":"driver@transitops.in","role":"DRIVER"}}',
              200,
            ),
          ),
        ),
        tokenStore: MemorySessionTokenStore(),
      );

      expect(
        await session.login(
          email: 'driver@transitops.in',
          password: 'password',
        ),
        isFalse,
      );
      expect(session.error, contains('mobile session token'));
      expect(session.error, isNot(contains("type 'Null'")));
    },
  );

  test(
    'driver login uses the dedicated endpoint and requires linkage',
    () async {
      final paths = <String>[];
      final session = SessionController(
        ApiClient(
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(
              '{"token":"driver-token","user":{"id":"user-1",'
              '"name":"Dispatcher","email":"dispatcher@transitops.in",'
              '"role":"DISPATCHER","organizationId":"org-1",'
              '"organizationName":"TransitOps","mustChangePassword":false}}',
              200,
            );
          }),
        ),
        tokenStore: MemorySessionTokenStore(),
      );

      expect(
        await session.login(
          email: 'dispatcher@transitops.in',
          password: 'Password@123',
          driverLogin: true,
        ),
        isFalse,
      );
      expect(paths.single, endsWith('/driver/auth/login'));
      expect(session.error, contains('not linked to a Driver profile'));
    },
  );

  test('password change atomically replaces the driver bearer token', () async {
    var requests = 0;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        requests++;
        if (requests == 1) {
          return http.Response(
            '{"token":"temporary-token","user":{"id":"user-1",'
            '"name":"Driver","email":"driver@transitops.in",'
            '"role":"DRIVER","driverId":"driver-1",'
            '"organizationId":"org-1","organizationName":"TransitOps",'
            '"mustChangePassword":true}}',
            200,
          );
        }
        expect(request.url.path, endsWith('/auth/change-password'));
        expect(request.headers['authorization'], 'Bearer temporary-token');
        return http.Response(
          '{"token":"replacement-token","user":{"id":"user-1",'
          '"name":"Driver","email":"driver@transitops.in",'
          '"role":"DRIVER","driverId":"driver-1",'
          '"organizationId":"org-1","organizationName":"TransitOps",'
          '"mustChangePassword":false}}',
          200,
        );
      }),
    );
    final tokenStore = MemorySessionTokenStore();
    final session = SessionController(api, tokenStore: tokenStore);
    await session.login(
      email: 'driver@transitops.in',
      password: 'Temporary@123',
      driverLogin: true,
    );

    expect(
      await session.changePassword(
        currentPassword: 'Temporary@123',
        newPassword: 'Permanent@123',
      ),
      isTrue,
    );
    expect(api.token, 'replacement-token');
    expect(tokenStore.token, 'replacement-token');
    expect(session.user?.mustChangePassword, isFalse);
  });

  test('unregisters push before clearing the authenticated session', () async {
    final api = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"token":"mobile-token","user":{"id":"user-1","name":"Raven Kumar","email":"driver@transitops.in","role":"DRIVER","organizationId":"org-1","organizationName":"TransitOps","mustChangePassword":false}}',
          200,
        ),
      ),
    );
    final session = SessionController(
      api,
      tokenStore: MemorySessionTokenStore(),
    );
    await session.login(email: 'driver@transitops.in', password: 'password');
    String? tokenDuringCallback;
    session.beforeLogout = () async {
      tokenDuringCallback = api.token;
    };

    await session.logout();

    expect(tokenDuringCallback, 'mobile-token');
    expect(api.token, isNull);
    expect(session.user, isNull);
  });
}
