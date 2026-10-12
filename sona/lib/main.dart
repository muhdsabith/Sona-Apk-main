import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'controllers/app_controller.dart';
import 'services/library_store.dart';
import 'services/audio_handler.dart';
import 'ui/app_shell.dart';
import 'ui/olam_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: cream,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RaagaApp());
}

class RaagaApp extends StatelessWidget {
  const RaagaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Raaga',
    theme: olamTheme(),
    builder: (_, child) =>
        RaagaBackdrop(child: child ?? const SizedBox.shrink()),
    home: const RaagaStartup(),
  );
}

class RaagaStartup extends StatefulWidget {
  const RaagaStartup({super.key});
  @override
  State<RaagaStartup> createState() => _RaagaStartupState();
}

class _RaagaStartupState extends State<RaagaStartup> {
  late final Future<AppController> _startup = _initialize();
  Future<AppController> _initialize() async {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Raaga / Musify-derived integration',
      ], await rootBundle.loadString('LICENSE'));
    });
    final handler = await AudioService.init<RaagaAudioHandler>(
      builder: RaagaAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.sona.audio',
        androidNotificationChannelName: 'Raaga playback',
        androidNotificationIcon: 'drawable/ic_stat_music',
        androidStopForegroundOnPause: true,
      ),
    );
    final controller = AppController(store: LibraryStore(), handler: handler);
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppController>(
    future: _startup,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Raaga could not start its audio service. Close and reopen the app. If this repeats, report the APK version (4.8.1).',
                ),
              ),
            ),
          ),
        );
      final controller = snapshot.data;
      if (controller == null)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return AppShell(controller: controller);
    },
  );
}
