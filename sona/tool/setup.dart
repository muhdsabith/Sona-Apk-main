import 'dart:io';

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync() || !Directory('lib').existsSync()) {
    stderr.writeln(
      'Run this command from the sona folder: dart tool/setup.dart',
    );
    exitCode = 1;
    return;
  }
  final command = Platform.isWindows ? 'flutter.bat' : 'flutter';
  Future<bool> run(List<String> arguments) async {
    stdout.writeln('flutter ${arguments.join(' ')}');
    try {
      final process = await Process.start(
        command,
        arguments,
        mode: ProcessStartMode.inheritStdio,
        runInShell: Platform.isWindows,
      );
      return await process.exitCode == 0;
    } on ProcessException {
      stderr.writeln(
        'Install Flutter and add its bin folder to PATH, then retry.',
      );
      return false;
    }
  }

  final preserved = <String, List<int>>{};
  for (final root in [
    'android/app/src/main/res',
    'ios/Runner/Assets.xcassets',
  ]) {
    final directory = Directory(root);
    if (directory.existsSync()) {
      for (final file
          in directory.listSync(recursive: true).whereType<File>()) {
        preserved[file.path] = file.readAsBytesSync();
      }
    }
  }
  final originalManifest = File('android/app/src/main/AndroidManifest.xml');
  if (originalManifest.existsSync())
    preserved[originalManifest.path] = originalManifest.readAsBytesSync();
  if (!await run([
    'create',
    '--empty',
    '--platforms=android,ios',
    '--project-name=sona',
    '--org=com.example',
    '--no-pub',
    '.',
  ])) {
    exitCode = 1;
    return;
  }
  for (final entry in preserved.entries) {
    final file = File(entry.key);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.value);
  }
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var xml = manifest.readAsStringSync();
    if (!xml.contains('android.permission.INTERNET')) {
      xml = xml.replaceFirstMapped(
        RegExp(r'(<manifest[^>]*>)'),
        (match) =>
            '${match.group(0)}\n'
            '    <uses-permission android:name="android.permission.INTERNET"/>',
      );
    }
    xml = xml.replaceFirst(
      RegExp(r'android:label="[^"]*"'),
      'android:label="Raaga"',
    );
    manifest.writeAsStringSync(xml);
  }
  final gradle = File('android/app/build.gradle.kts');
  if (gradle.existsSync()) {
    gradle.writeAsStringSync(
      gradle.readAsStringSync().replaceFirst(
        'minSdk = flutter.minSdkVersion',
        'minSdk = 24',
      ),
    );
  }
  final legacyGradle = File('android/app/build.gradle');
  if (legacyGradle.existsSync()) {
    legacyGradle.writeAsStringSync(
      legacyGradle
          .readAsStringSync()
          .replaceFirst(
            'minSdkVersion flutter.minSdkVersion',
            'minSdkVersion 24',
          )
          .replaceFirst('minSdk flutter.minSdkVersion', 'minSdk 24'),
    );
  }
  final xcode = File('ios/Runner.xcodeproj/project.pbxproj');
  if (xcode.existsSync()) {
    xcode.writeAsStringSync(
      xcode.readAsStringSync().replaceAllMapped(
        RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);'),
        (match) {
          final parts = match.group(1)!.split('.').map(int.parse).toList();
          final older =
              parts.first < 17 ||
              (parts.first == 17 && (parts.length > 1 ? parts[1] : 0) < 4);
          return older ? 'IPHONEOS_DEPLOYMENT_TARGET = 17.4;' : match.group(0)!;
        },
      ),
    );
  }
  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    final text = podfile.readAsStringSync();
    final pattern = RegExp(r"^#?\s*platform :ios, '[0-9.]+'", multiLine: true);
    podfile.writeAsStringSync(
      text.replaceAllMapped(pattern, (match) {
        final version = RegExp(
          r"'([0-9.]+)'",
        ).firstMatch(match.group(0)!)!.group(1)!;
        final parts = version.split('.').map(int.parse).toList();
        final older =
            parts.first < 17 ||
            (parts.first == 17 && (parts.length > 1 ? parts[1] : 0) < 4);
        return older
            ? "platform :ios, '17.4'"
            : match.group(0)!.replaceFirst(RegExp(r'^#\s*'), '');
      }),
    );
  }
  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    var text = plist.readAsStringSync();
    for (final key in ['CFBundleDisplayName', 'CFBundleName']) {
      final pattern = RegExp('(<key>$key</key>\\s*<string>)[^<]*(</string>)');
      if (pattern.hasMatch(text)) {
        text = text.replaceAllMapped(
          pattern,
          (match) => '${match.group(1)}Raaga${match.group(2)}',
        );
      } else {
        text = text.replaceFirst(
          '</dict>',
          '<key>$key</key><string>Raaga</string></dict>',
        );
      }
    }
    if (!text.contains('<key>UIBackgroundModes</key>')) {
      text = text.replaceFirst(
        '</dict>',
        '<key>UIBackgroundModes</key><array><string>audio</string></array></dict>',
      );
    }
    plist.writeAsStringSync(text);
  }

  if (!await run(['pub', 'get'])) {
    exitCode = 1;
    return;
  }
  if (!await run(['analyze', '--no-fatal-infos', '--no-fatal-warnings'])) {
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Ready. Connect an Android device or start an iOS simulator, then run flutter run.',
  );
}
