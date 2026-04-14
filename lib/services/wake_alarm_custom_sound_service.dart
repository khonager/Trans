import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'wake_alarm_settings.dart';

class WakeAlarmCustomSoundService {
  static const List<String> allowedExtensions = [
    'aac',
    'aif',
    'aiff',
    'caf',
    'flac',
    'm4a',
    'mp3',
    'ogg',
    'wav',
  ];

  static Future<WakeAlarmSoundOption?> pickAndImport() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final sourcePath = picked.path;
    if (sourcePath == null || sourcePath.isEmpty) return null;

    return importFromPath(
      sourcePath,
      originalFileName: picked.name,
    );
  }

  static Future<WakeAlarmSoundOption> importFromPath(
    String sourcePath, {
    String? originalFileName,
  }) async {
    final sourceFile = File(sourcePath);
    final supportDirectory = await getApplicationSupportDirectory();
    final soundsDirectory = Directory(
      '${supportDirectory.path}/wake_alarm_sounds',
    );
    if (!await soundsDirectory.exists()) {
      await soundsDirectory.create(recursive: true);
    }

    final extension = _normalizedExtension(originalFileName ?? sourcePath);
    final storedFileName = 'custom_alarm_sound.$extension';
    final storedFile = File('${soundsDirectory.path}/$storedFileName');
    await sourceFile.copy(storedFile.path);

    final label = _displayLabel(originalFileName ?? sourcePath);
    await WakeAlarmSettings.setCustomSound(
      localFilePath: storedFile.path,
      fileName: storedFileName,
      label: label,
    );
    return WakeAlarmSettings.soundForId(WakeAlarmSettings.customSoundId);
  }

  static String _normalizedExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return 'mp3';
    }

    final extension = path.substring(dotIndex + 1).toLowerCase();
    if (allowedExtensions.contains(extension)) {
      return extension;
    }
    return 'mp3';
  }

  static String _displayLabel(String path) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName;
    return fileName.substring(0, dotIndex);
  }
}
