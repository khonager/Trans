import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'wake_alarm_settings.dart';

class WakeAlarmPreviewPlayer {
  static const MethodChannel _channel =
      MethodChannel('de.khonager.trans/wake_alarm_preview');

  static Process? _desktopProcess;

  static Future<bool> play(WakeAlarmSoundOption sound) async {
    if (!sound.playSound) {
      await stop();
      return true;
    }

    final localFilePath = sound.localFilePath;
    if (localFilePath != null && localFilePath.isNotEmpty) {
      final file = File(localFilePath);
      if (await file.exists()) {
        if (Platform.isAndroid || Platform.isIOS) {
          return _playWithMethodChannel(file.path);
        }
        if (Platform.isLinux) {
          return _playWithDesktopCommand([
            ['pw-play', file.path],
            ['paplay', file.path],
            ['aplay', file.path],
            ['canberra-gtk-play', '-f', file.path],
          ]);
        }
        if (Platform.isMacOS) {
          return _playWithDesktopCommand([
            ['afplay', file.path],
          ]);
        }
        if (Platform.isWindows) {
          return _playWithDesktopCommand([
            [
              'powershell.exe',
              '-NoProfile',
              '-Command',
              '(New-Object Media.SoundPlayer \$args[0]).PlaySync()',
              file.path,
            ],
            [
              'powershell',
              '-NoProfile',
              '-Command',
              '(New-Object Media.SoundPlayer \$args[0]).PlaySync()',
              file.path,
            ],
          ]);
        }
      }
    }

    final fileName = sound.fileName;
    final assetPath = sound.assetPath;
    if (fileName == null || assetPath == null) return false;

    final file = await _writePreviewAsset(fileName, assetPath);

    if (Platform.isAndroid || Platform.isIOS) {
      return _playWithMethodChannel(file.path);
    }
    if (Platform.isLinux) {
      return _playWithDesktopCommand([
        ['pw-play', file.path],
        ['paplay', file.path],
        ['aplay', file.path],
        ['canberra-gtk-play', '-f', file.path],
      ]);
    }
    if (Platform.isMacOS) {
      return _playWithDesktopCommand([
        ['afplay', file.path],
      ]);
    }
    if (Platform.isWindows) {
      return _playWithDesktopCommand([
        [
          'powershell.exe',
          '-NoProfile',
          '-Command',
          '(New-Object Media.SoundPlayer \$args[0]).PlaySync()',
          file.path,
        ],
        [
          'powershell',
          '-NoProfile',
          '-Command',
          '(New-Object Media.SoundPlayer \$args[0]).PlaySync()',
          file.path,
        ],
      ]);
    }

    return false;
  }

  static Future<void> stop() async {
    _desktopProcess?.kill();
    _desktopProcess = null;

    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Desktop/web previews do not use the platform channel.
    }
  }

  static Future<File> _writePreviewAsset(
    String fileName,
    String assetPath,
  ) async {
    final directory =
        Directory('${(await getTemporaryDirectory()).path}/wake_alarm_preview');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/$fileName');
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }

    return file;
  }

  static Future<bool> _playWithMethodChannel(String path) async {
    try {
      await _channel.invokeMethod<void>('play', {'path': path});
      return true;
    } on MissingPluginException {
      if (Platform.isIOS || Platform.isAndroid) {
        throw StateError(
          'The native alarm preview player was not registered. Restart the app and try again.',
        );
      }
      return false;
    }
  }

  static Future<bool> _playWithDesktopCommand(
    List<List<String>> commands,
  ) async {
    await stop();

    for (final command in commands) {
      try {
        final process = await Process.start(
          command.first,
          command.skip(1).toList(growable: false),
        );
        _desktopProcess = process;
        unawaited(process.exitCode.then((_) {
          if (identical(_desktopProcess, process)) {
            _desktopProcess = null;
          }
        }));
        return true;
      } on ProcessException {
        continue;
      }
    }

    return false;
  }
}
