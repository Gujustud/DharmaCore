import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'auth_gate.dart' show AuthGate, dharmaCoreNavigatorKey;
import 'combined_home_screen.dart';
import 'drawer_data_cache.dart';
import 'http_client_factory.dart';
import 'app_config.dart';
import 'pocketbase_service.dart';
import 'theme_controller.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HttpClientFactory.init;
  await PocketBaseService.init;
  await ThemeController.instance.load();
  await DrawerDataCache.preload();
  final hasInvalidReleaseConfig = kReleaseMode &&
      (_isLocalhostEndpoint(AppConfig.pocketBaseUrl) ||
          _isLocalhostEndpoint(AppConfig.mcpUrl));
  if (hasInvalidReleaseConfig) {
    runApp(const _MisconfiguredReleaseApp());
    return;
  }
  runApp(const DharmaCoreApp());
}
bool _isLocalhostEndpoint(String rawUrl) {
  final trimmed = rawUrl.trim().toLowerCase();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains('localhost')) return true;
  final uri = Uri.tryParse(trimmed);
  final host = uri?.host.toLowerCase() ?? '';
  return host == '127.0.0.1' || host == '::1';
}

class _MisconfiguredReleaseApp extends StatelessWidget {
  const _MisconfiguredReleaseApp();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DharmaCore',
      theme: AppTheme.of(AppSkin.precision, Brightness.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('DharmaCore configuration error')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            'This release build is using localhost URLs and cannot connect on mobile devices.\n\n'
            'Rebuild the APK using production dart-defines:\n\n'
            'flutter build apk --release '
            '--dart-define=POCKETBASE_URL=https://cribhub.sscadcam.com/ '
            '--dart-define=MCP_URL=https://cribhub.sscadcam.com/mcp\n\n'
            'Or from repo root: .\\scripts\\buildapk.bat\n\n'
            'Current values:\n'
            'POCKETBASE_URL=${AppConfig.pocketBaseUrl}\n'
            'MCP_URL=${AppConfig.mcpUrl}',
          ),
        ),
      ),
    );
  }
}

class DharmaCoreApp extends StatelessWidget {
  const DharmaCoreApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSkin>(
      valueListenable: ThemeController.instance.skin,
      builder: (context, skin, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.instance.themeMode,
          builder: (context, mode, _) {
            return MaterialApp(
              navigatorKey: dharmaCoreNavigatorKey,
              title: 'DharmaCore',
              theme: AppTheme.of(skin, Brightness.light),
              darkTheme: AppTheme.of(skin, Brightness.dark),
              themeMode: mode,
              home: const AuthGate(child: CombinedHomeScreen()),
            );
          },
        );
      },
    );
  }
}
