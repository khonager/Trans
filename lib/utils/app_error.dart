import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';

class AppError {
  static String userMessage(
    BuildContext context,
    Object error, {
    String? fallback,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final fallbackMessage = fallback ?? l10n.serviceBusyPleaseTryAgain;

    if (error is TimeoutException) {
      return l10n.requestTimedOut;
    }

    if (error is AuthException) {
      return _authMessage(context, error.message, fallbackMessage);
    }

    if (error is PostgrestException) {
      return _postgrestMessage(context, error, fallbackMessage);
    }

    if (error is String) {
      return _sanitizeText(error, fallbackMessage);
    }

    final raw = error.toString();
    if (_looksLikeNetworkFailure(raw)) {
      return l10n.serviceBusyPleaseTryAgain;
    }

    return _sanitizeText(raw, fallbackMessage);
  }

  static void log(
    Object error, {
    StackTrace? stackTrace,
    required String source,
  }) {
    debugPrint('[AppError][$source] ${error.runtimeType}: $error');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  static Future<void> showSnackBar(
    BuildContext context, {
    required Object error,
    StackTrace? stackTrace,
    required String source,
    String? fallback,
  }) async {
    log(error, stackTrace: stackTrace, source: source);
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final message = userMessage(context, error, fallback: fallback);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: _isGerman(context) ? 'Melden' : 'Report',
          onPressed: () {
            unawaited(
              _showReportDialog(
                context,
                error: error,
                stackTrace: stackTrace,
                source: source,
                userMessage: message,
              ),
            );
          },
        ),
      ),
    );
  }

  static Future<void> _showReportDialog(
    BuildContext context, {
    required Object error,
    StackTrace? stackTrace,
    required String source,
    required String userMessage,
  }) async {
    final report = _buildReport(
      error: error,
      stackTrace: stackTrace,
      source: source,
      userMessage: userMessage,
    );

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final isGerman = _isGerman(dialogContext);
        return AlertDialog(
          title:
              Text(isGerman ? 'Fehlerbericht senden?' : 'Send error report?'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isGerman
                    ? 'Das wird genau gesendet:'
                    : 'This is exactly what will be sent:'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 260),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      report,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(dialogContext)!.cancel),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                          isGerman ? 'Bericht kopiert.' : 'Report copied.'),
                    ),
                  );
                }
              },
              child: Text(isGerman ? 'Kopieren' : 'Copy'),
            ),
            ElevatedButton(
              onPressed: () async {
                final opened = await _openMailDraft(source, report);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(opened
                        ? (isGerman
                            ? 'E-Mail-Entwurf geöffnet.'
                            : 'Email draft opened.')
                        : (isGerman
                            ? 'E-Mail-App konnte nicht geöffnet werden.'
                            : "Couldn't open email app.")),
                  ),
                );
              },
              child: Text(isGerman ? 'Senden' : 'Send'),
            ),
          ],
        );
      },
    );
  }

  static String _buildReport({
    required Object error,
    StackTrace? stackTrace,
    required String source,
    required String userMessage,
  }) {
    final shortStack =
        stackTrace?.toString().split('\n').take(30).join('\n').trim();
    final mode =
        kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

    return [
      'Trans Error Report',
      'Generated UTC: ${DateTime.now().toUtc().toIso8601String()}',
      'Source: $source',
      'Platform: ${defaultTargetPlatform.name}',
      'Mode: $mode',
      '',
      'User Message: $userMessage',
      'Error Type: ${error.runtimeType}',
      'Error: $error',
      '',
      'Stack Trace:',
      shortStack == null || shortStack.isEmpty ? '(not available)' : shortStack,
    ].join('\n');
  }

  static Future<bool> _openMailDraft(String source, String report) async {
    final subject = 'Trans error report: $source';
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.supportEmail,
      queryParameters: {
        'subject': subject,
        'body': report,
      },
    );
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }

  static String _authMessage(
    BuildContext context,
    String raw,
    String fallback,
  ) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials')) {
      return _isGerman(context)
          ? 'Anmeldung fehlgeschlagen. Bitte E-Mail und Passwort prüfen.'
          : 'Sign-in failed. Please check your email and password.';
    }
    if (lower.contains('email not confirmed')) {
      return _isGerman(context)
          ? 'Bitte bestätige zuerst deine E-Mail-Adresse.'
          : 'Please confirm your email address first.';
    }
    if (lower.contains('user already registered')) {
      return _isGerman(context)
          ? 'Für diese E-Mail gibt es bereits ein Konto.'
          : 'An account with this email already exists.';
    }
    if (lower.contains('same_password')) {
      return _isGerman(context)
          ? 'Bitte ein anderes Passwort wählen.'
          : 'Please choose a different password.';
    }
    if (_looksLikeNetworkFailure(lower)) {
      return AppLocalizations.of(context)!.serviceBusyPleaseTryAgain;
    }
    return fallback;
  }

  static String _postgrestMessage(
    BuildContext context,
    PostgrestException error,
    String fallback,
  ) {
    final raw = error.message;
    final lower = raw.toLowerCase();
    if (error.code == '42501' &&
        lower.contains('row-level security policy') &&
        lower.contains('profiles')) {
      return _isGerman(context)
          ? 'Registrierung konnte nicht abgeschlossen werden. Möglicherweise existiert das Konto bereits oder die E-Mail muss noch bestätigt werden.'
          : 'Sign-up could not be completed. The account may already exist or the email still needs confirmation.';
    }
    if (lower.contains('duplicate key value') && lower.contains('username')) {
      return _isGerman(context)
          ? 'Dieser Benutzername ist bereits vergeben.'
          : 'That username is already taken.';
    }
    if (lower.contains('duplicate key value') && lower.contains('email')) {
      return _isGerman(context)
          ? 'Für diese E-Mail gibt es bereits ein Konto.'
          : 'An account with this email already exists.';
    }
    if (_looksLikeNetworkFailure(lower)) {
      return AppLocalizations.of(context)!.serviceBusyPleaseTryAgain;
    }
    return fallback;
  }

  static String _sanitizeText(String text, String fallback) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return fallback;
    if (_looksTechnical(trimmed)) return fallback;
    return trimmed;
  }

  static bool _looksTechnical(String value) {
    final lower = value.toLowerCase();
    const markers = <String>[
      'exception',
      'postgres',
      'postgrest',
      'socketexception',
      'authapierror',
      'status code',
      'stack trace',
      'rpc',
      'sql',
      'constraint',
      'violates',
      'function ',
      'null value in column',
      'failed host lookup',
    ];
    return markers.any(lower.contains);
  }

  static bool _looksLikeNetworkFailure(String value) {
    final lower = value.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection reset by peer') ||
        lower.contains('timed out');
  }

  static bool _isGerman(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'de';
  }
}
