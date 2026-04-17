import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import 'supabase_service.dart';

class CommunitySafetyService {
  static const String _termsAcceptedKey = 'community_terms_accepted_v1';

  static bool _isGerman(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'de';

  static Future<bool> hasAcceptedTerms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_termsAcceptedKey) ?? false;
  }

  static Future<void> showCommunityTerms(BuildContext context) async {
    await _showTermsDialog(context, requireAcceptance: false);
  }

  static Future<bool> ensureTermsAccepted(
    BuildContext context, {
    String? entryPoint,
  }) async {
    if (await hasAcceptedTerms()) return true;
    if (!context.mounted) return false;

    final accepted = await _showTermsDialog(
      context,
      requireAcceptance: true,
      entryPoint: entryPoint,
    );
    if (!accepted) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_termsAcceptedKey, true);
    return true;
  }

  static Future<bool> _showTermsDialog(
    BuildContext context, {
    required bool requireAcceptance,
    String? entryPoint,
  }) async {
    final isGerman = _isGerman(context);
    final intro = switch ((isGerman, requireAcceptance)) {
      (true, true) when entryPoint != null =>
        'Bevor du $entryPoint nutzen kannst, musst du diesen Nutzungsbedingungen zustimmen:',
      (false, true) when entryPoint != null =>
        'Before you can access $entryPoint, you must agree to these terms:',
      (true, true) =>
        'Bevor du nutzergenerierte Inhalte nutzen kannst, musst du diesen Nutzungsbedingungen zustimmen:',
      (false, true) =>
        'Before you can access user-generated content, you must agree to these terms:',
      (true, false) =>
        'Diese Regeln gelten für Chats, Profile und Freundesfunktionen:',
      (false, false) =>
        'These rules apply to chats, profiles, and friend features:',
    };

    final bullets = <String>[
      isGerman
          ? 'Keine Toleranz für belästigende, beleidigende, sexuelle, hasserfüllte, gewalttätige oder anderweitig anstößige Inhalte.'
          : 'No tolerance for harassing, abusive, sexual, hateful, violent, or otherwise objectionable content.',
      isGerman
          ? 'Keine Toleranz für Spam, Betrug, Nachahmung oder wiederholt missbräuchliches Verhalten.'
          : 'No tolerance for spam, scams, impersonation, or repeated abusive behavior.',
      isGerman
          ? 'Nutzer können Inhalte melden und missbräuchliche Nutzer blockieren.'
          : 'Users can report content and block abusive users.',
      isGerman
          ? 'Verstöße können zur Entfernung von Inhalten oder zur Sperrung des Kontos führen.'
          : 'Violations can lead to content removal or account suspension.',
    ];

    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: !requireAcceptance,
          builder: (dialogContext) => AlertDialog(
            title: Text(isGerman
                ? 'Nutzungsbedingungen & Community-Regeln'
                : 'Terms of Use & Community Rules'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(intro),
                    const SizedBox(height: 12),
                    for (final bullet in bullets) ...[
                      Text('\u2022 $bullet'),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      isGerman
                          ? 'Wenn du fortfährst, bestätigst du, dass du diese Regeln einhältst.'
                          : 'By continuing, you confirm that you will follow these rules.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(isGerman
                    ? (requireAcceptance ? 'Nicht jetzt' : 'Schließen')
                    : (requireAcceptance ? 'Not now' : 'Close')),
              ),
              if (requireAcceptance)
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                      isGerman ? 'Zustimmen & fortfahren' : 'Agree & Continue'),
                ),
            ],
          ),
        ) ??
        false;

    return accepted;
  }

  static Future<void> showReportDialog(
    BuildContext context, {
    required String contentType,
    required String targetId,
    String? targetLabel,
    String? reportedUserId,
    String? reportedUsername,
    String? messagePreview,
    String source = 'community safety',
  }) async {
    if (!context.mounted) return;

    final isGerman = _isGerman(context);
    const englishReasons = [
      'Harassment or abuse',
      'Hate or discrimination',
      'Sexual or explicit content',
      'Violence or threats',
      'Spam or scam',
      'Other',
    ];
    const germanReasons = [
      'Belästigung oder Missbrauch',
      'Hass oder Diskriminierung',
      'Sexuelle oder explizite Inhalte',
      'Gewalt oder Drohungen',
      'Spam oder Betrug',
      'Sonstiges',
    ];
    final reasons = isGerman ? germanReasons : englishReasons;

    var selectedReason = reasons.first;
    var includeMessageHistory = false;
    final detailsCtrl = TextEditingController();

    try {
      final submitted = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Text(isGerman ? 'Inhalt melden' : 'Report content'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(isGerman
                            ? 'Warum möchtest du das melden?'
                            : 'Why do you want to report this?'),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedReason,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          items: reasons
                              .map((reason) => DropdownMenuItem(
                                    value: reason,
                                    child: Text(reason),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => selectedReason = value);
                            }
                          },
                        ),
                        if (targetLabel != null && targetLabel.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            '${isGerman ? 'Kontext' : 'Context'}: $targetLabel',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                        if (messagePreview != null &&
                            messagePreview.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            isGerman
                                ? 'Nachrichtenvorschau'
                                : 'Message preview',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(messagePreview),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: detailsCtrl,
                          minLines: 3,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: isGerman
                                ? 'Weitere Details (optional)'
                                : 'Additional details (optional)',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        if (contentType.contains('message') ||
                            contentType.contains('chat')) ...[
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: includeMessageHistory,
                            onChanged: (value) {
                              setState(
                                  () => includeMessageHistory = value ?? false);
                            },
                            title: Text(isGerman
                                ? 'Vollständigen Nachrichtenverlauf mit diesem Nutzer einbeziehen'
                                : 'Include full message history with this user'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          Text(
                            isGerman
                                ? 'Hinweis: Bei Auswahl können Nachrichteninhalte in deiner E-Mail-App und bei deinem Mail-Anbieter sichtbar sein.'
                                : 'Note: If selected, message content may be visible in your email app and email provider.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(isGerman ? 'Abbrechen' : 'Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(isGerman ? 'Melden' : 'Report'),
                  ),
                ],
              ),
            ),
          ) ??
          false;

      if (!submitted || !context.mounted) return;

      String? messageHistory;
      if (includeMessageHistory && reportedUserId != null) {
        messageHistory = await _fetchMessageHistory(
          contentType: contentType,
          reportedUserId: reportedUserId,
          targetId: targetId,
        );
      }

      final report = _buildReport(
        source: source,
        contentType: contentType,
        targetId: targetId,
        targetLabel: targetLabel,
        reportedUserId: reportedUserId,
        reportedUsername: reportedUsername,
        messagePreview: messagePreview,
        reason: selectedReason,
        details: detailsCtrl.text.trim(),
        includeMessageHistory: includeMessageHistory,
        messageHistory: messageHistory,
      );

      final messenger = ScaffoldMessenger.of(context);
      final opened = await _openMailDraft(
        subject: isGerman ? 'Trans Inhaltsmeldung' : 'Trans content report',
        body: report,
      );

      if (!context.mounted) return;
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: report));
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(opened
              ? (isGerman
                  ? 'E-Mail-Entwurf für die Meldung geöffnet.'
                  : 'Email draft opened for the report.')
              : (isGerman
                  ? 'Mail-App nicht verfügbar. Meldung wurde in die Zwischenablage kopiert.'
                  : 'Mail app unavailable. The report was copied to your clipboard.')),
        ),
      );
    } finally {
      detailsCtrl.dispose();
    }
  }

  static String _buildReport({
    required String source,
    required String contentType,
    required String targetId,
    String? targetLabel,
    String? reportedUserId,
    String? reportedUsername,
    String? messagePreview,
    required String reason,
    required String details,
    bool includeMessageHistory = false,
    String? messageHistory,
  }) {
    final reporterId = SupabaseService.currentUser?.id ?? '(not signed in)';
    final reporterEmail =
        SupabaseService.currentUser?.email ?? '(email unavailable)';

    final sections = [
      'Trans Content Report',
      'Generated UTC: ${DateTime.now().toUtc().toIso8601String()}',
      'Source: $source',
      '',
      'Reporter User ID: $reporterId',
      'Reporter Email: $reporterEmail',
      '',
      'Content Type: $contentType',
      'Target ID: $targetId',
      'Target Label: ${targetLabel ?? '(not provided)'}',
      'Reported User ID: ${reportedUserId ?? '(not provided)'}',
      'Reported Username: ${reportedUsername ?? '(not provided)'}',
      'Reason: $reason',
      'Include Message History: ${includeMessageHistory ? 'YES' : 'NO'}',
      '',
      'Message Preview:',
      messagePreview == null || messagePreview.trim().isEmpty
          ? '(not provided)'
          : messagePreview,
      '',
      'Additional Details:',
      details.isEmpty ? '(not provided)' : details,
    ];

    if (messageHistory != null && messageHistory.isNotEmpty) {
      sections.addAll([
        '',
        '=' * 70,
        'FULL MESSAGE HISTORY',
        '=' * 70,
        '',
        messageHistory,
      ]);
    }

    return sections.join('\n');
  }

  static Future<String?> _fetchMessageHistory({
    required String contentType,
    required String reportedUserId,
    required String targetId,
  }) async {
    try {
      final myId = SupabaseService.currentUser?.id;
      if (myId == null) return null;

      List<Map<String, dynamic>> messages;

      if (contentType.contains('private')) {
        // Fetch private messages between the two users
        messages = await SupabaseService.client
            .from('messages')
            .select('created_at, user_id, receiver_id, content, is_encrypted')
            .eq('is_encrypted', true)
            .or(
                'and(user_id.eq.$myId,receiver_id.eq.$reportedUserId),and(user_id.eq.$reportedUserId,receiver_id.eq.$myId)')
            .order('created_at', ascending: true)
            .limit(200);
      } else {
        // For public chat, fetch from the specific line/channel
        final lineId =
            targetId.contains(':') ? targetId.split(':').first : targetId;

        messages = await SupabaseService.client
            .from('messages')
            .select('created_at, user_id, content')
            .eq('line_id', lineId)
            .order('created_at', ascending: true)
            .limit(200);
      }

      if (messages.isEmpty) return null;

      final buffer = StringBuffer();
      for (final msg in messages) {
        final timestamp = msg['created_at'] ?? '';
        final userId = msg['user_id'] ?? '';
        final isEncrypted = msg['is_encrypted'] == true;
        final rawContent = (msg['content'] ?? '').toString();
        final content = isEncrypted
            ? _decryptPrivateMessage(
                myId: myId,
                otherUserId: reportedUserId,
                storedContent: rawContent,
              )
            : (rawContent.isEmpty ? '[unavailable]' : rawContent);
        final isMe = userId == myId;
        final sender = isMe
            ? 'Me'
            : (userId == reportedUserId ? 'Reported User' : 'Other User');

        buffer.writeln('[$timestamp] $sender:');
        buffer.writeln(content);
        buffer.writeln();
      }

      return buffer.toString();
    } catch (e) {
      // If fetching fails, return error message instead of crashing
      return '(Error fetching message history: $e)';
    }
  }

  static Future<bool> _openMailDraft({
    required String subject,
    required String body,
  }) async {
    // Manually encode to use %20 for spaces instead of +
    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);
    final uri = Uri.parse(
        'mailto:${AppConfig.supportEmail}?subject=$encodedSubject&body=$encodedBody');
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }

  static String _decryptPrivateMessage({
    required String myId,
    required String otherUserId,
    required String storedContent,
  }) {
    if (storedContent.isEmpty) return '[encrypted or unavailable]';

    try {
      final keyString = _buildPrivateKey(myId, otherUserId);
      final key = enc.Key.fromUtf8(keyString);
      final encrypter = enc.Encrypter(enc.AES(key));
      final parts = storedContent.split(':');
      if (parts.length != 2) return '[corrupt encrypted message]';
      final iv = enc.IV.fromBase64(parts[0]);
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (_) {
      return '[error decrypting]';
    }
  }

  static String _buildPrivateKey(String myId, String otherUserId) {
    final ids = [myId, otherUserId]..sort();
    final digest = sha256.convert(utf8.encode(ids.join('_')));
    return digest.toString().substring(0, 32);
  }
}
