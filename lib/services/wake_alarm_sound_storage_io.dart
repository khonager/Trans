import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'wake_alarm_settings.dart';

Future<void> ensureDarwinWakeAlarmSounds(
    List<WakeAlarmSoundOption> sounds) async {
  final libraryDirectory = await getLibraryDirectory();
  final soundsDirectory = Directory('${libraryDirectory.path}/Sounds');
  if (!await soundsDirectory.exists()) {
    await soundsDirectory.create(recursive: true);
  }

  for (final sound in sounds) {
    final assetPath = sound.assetPath;
    final fileName = sound.fileName;
    if (assetPath == null || fileName == null) continue;

    final file = File('${soundsDirectory.path}/$fileName');
    if (await file.exists()) continue;

    final byteData = await rootBundle.load(assetPath);
    await file.writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      flush: true,
    );
  }
}
