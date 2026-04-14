import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
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
    if (!await sourceFile.exists()) {
      throw const FileSystemException('Selected file no longer exists.');
    }
    if (!await _isSupportedAudioFile(sourceFile, originalFileName ?? sourcePath)) {
      throw const FileSystemException(
        'Please choose an audio file such as MP3, WAV, M4A, OGG, FLAC, AIFF, AAC, or CAF.',
      );
    }

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
    final baseName = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
    final compact = baseName.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (compact.length <= 24) return compact;
    return '${compact.substring(0, 21).trimRight()}...';
  }

  static Future<void> deleteCustomSound() async {
    final localPath = WakeAlarmSettings.soundOptions
        .where((option) => option.id == WakeAlarmSettings.customSoundId)
        .map((option) => option.localFilePath)
        .cast<String?>()
        .firstWhere(
          (path) => path != null && path.isNotEmpty,
          orElse: () => null,
        );
    if (localPath != null) {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await WakeAlarmSettings.clearCustomSound();
  }

  static Future<bool> _isSupportedAudioFile(File file, String name) async {
    final extension = _fileExtension(name);
    if (extension == null || !allowedExtensions.contains(extension)) {
      return false;
    }

    final headerBytes = await file.openRead(0, 32).fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    final mimeType = lookupMimeType(name, headerBytes: headerBytes);
    if (mimeType == null) {
      return true;
    }
    return mimeType.startsWith('audio/');
  }

  static String? _fileExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return null;
    }
    return path.substring(dotIndex + 1).toLowerCase();
  }
}
