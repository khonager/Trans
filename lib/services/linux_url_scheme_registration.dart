import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/app_error.dart';

class LinuxUrlSchemeRegistration {
  static const String _scheme = 'io.supabase.trans';
  static const String _desktopFileName = 'de.khonager.trans.desktop';

  static Future<void> ensureRegistered() async {
    if (!Platform.isLinux) return;

    try {
      final executablePath =
          await File('/proc/self/exe').resolveSymbolicLinks();
      final applicationsDir = Directory(
          '${Platform.environment['HOME']}/.local/share/applications');

      if (!applicationsDir.existsSync()) {
        await applicationsDir.create(recursive: true);
      }

      final desktopFile = File('${applicationsDir.path}/$_desktopFileName');
      final desktopEntry = _desktopEntryFor(executablePath);

      if (!desktopFile.existsSync() ||
          await desktopFile.readAsString() != desktopEntry) {
        await desktopFile.writeAsString(desktopEntry);
      }

      await _tryRun('update-desktop-database', [applicationsDir.path]);
      await _tryRun(
        'xdg-mime',
        ['default', _desktopFileName, 'x-scheme-handler/$_scheme'],
      );
    } catch (e, st) {
      AppError.log(
        e,
        stackTrace: st,
        source: 'LinuxUrlSchemeRegistration.ensureRegistered',
      );
    }
  }

  static String _desktopEntryFor(String executablePath) {
    return '''
[Desktop Entry]
Version=1.0
Type=Application
Name=Trans
Comment=Trans desktop URL handler
Exec=$executablePath %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/$_scheme;
Categories=Utility;
StartupNotify=false
''';
  }

  static Future<void> _tryRun(String command, List<String> arguments) async {
    try {
      final result = await Process.run(command, arguments);
      if (result.exitCode != 0) {
        throw ProcessException(
          command,
          arguments,
          result.stderr.toString(),
          result.exitCode,
        );
      }
    } on ProcessException catch (e, st) {
      if (e.message.contains('No such file or directory')) {
        debugPrint(
          'Skipping Linux URL scheme helper "$command" because it is not installed.',
        );
        return;
      }
      AppError.log(
        e,
        stackTrace: st,
        source: 'LinuxUrlSchemeRegistration._tryRun($command)',
      );
    }
  }
}
