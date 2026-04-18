import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'supabase_service.dart';

class ColorClaimException implements Exception {
  final String message;

  const ColorClaimException(this.message);

  @override
  String toString() => message;
}

class ColorClaimStatus {
  final String hex;
  final String hexId;
  final bool transClaimedByOther;
  final bool transClaimedByCurrentUser;
  final String? transOwnerLabel;
  final String? transOwnerUserId;
  final bool portfolioClaimedByOther;
  final bool portfolioClaimedByCurrentUser;
  final String? portfolioOwnerLabel;
  final String? portfolioOwnerUid;
  final bool portfolioStatusChecked;

  const ColorClaimStatus({
    required this.hex,
    required this.hexId,
    required this.transClaimedByOther,
    required this.transClaimedByCurrentUser,
    required this.transOwnerLabel,
    required this.transOwnerUserId,
    required this.portfolioClaimedByOther,
    required this.portfolioClaimedByCurrentUser,
    required this.portfolioOwnerLabel,
    required this.portfolioOwnerUid,
    required this.portfolioStatusChecked,
  });

  bool get isUnavailableInTrans => transClaimedByOther;
  bool get isAvailableInTrans => !transClaimedByOther;
  bool get isTransOnlyAvailability =>
      isAvailableInTrans && portfolioClaimedByOther;
}

class ColorClaimResult {
  final String hex;
  final String hexId;
  final bool syncedToPortfolio;
  final bool attemptedPortfolioSync;
  final String? syncMessage;

  const ColorClaimResult({
    required this.hex,
    required this.hexId,
    required this.syncedToPortfolio,
    required this.attemptedPortfolioSync,
    required this.syncMessage,
  });
}

class ColorClaimService {
  static const String appId = 'trans';
  static const String _claimsTable = 'trans_color_claims';
  static const String _settingsClaimKey = 'theme_color_claim';

  static String normalizeHex(String input) {
    final trimmed = input.trim();
    final raw = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (raw.length != 6 || !_isHex(raw)) {
      throw const ColorClaimException('Only 6-digit hex colors are supported.');
    }
    return '#${raw.toLowerCase()}';
  }

  static String hexIdFromHex(String hex) => normalizeHex(hex).substring(1);

  static String normalizeColor(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toLowerCase()}';
  }

  static Future<ColorClaimStatus> checkAvailability(
    Color color, {
    Map<String, dynamic>? currentProfile,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      throw const ColorClaimException(
          'You need to be signed in to save a theme color.');
    }

    final hex = normalizeColor(color);
    final hexId = hexIdFromHex(hex);
    final profile = currentProfile ?? await SupabaseService.getCurrentProfile();
    final linkedPortfolioUid = _extractLinkedPortfolioUid(profile);
    final localRow = await _getLocalClaim(hexId);

    final localOwnerUserId = localRow?['external_user_id']?.toString();
    final localOwnerLabel = localRow?['owner_label']?.toString();
    final transClaimedByOther = localRow != null &&
        localOwnerUserId != null &&
        localOwnerUserId != user.id;
    final transClaimedByCurrentUser =
        localRow != null && localOwnerUserId == user.id;

    final remote = await _fetchPortfolioStatus(
      hex: hex,
      hexId: hexId,
      externalUserId: user.id,
      linkedPortfolioUid: linkedPortfolioUid,
    );

    final rootClaim = _asMap(remote?['rootClaim']);
    final appClaim = _asMap(remote?['appClaim']);
    final remoteAppActive = appClaim?['active'] == true;
    final remoteAppUserId = appClaim?['externalUserId']?.toString();
    final remoteAppOwnedByOther = remoteAppActive &&
        remoteAppUserId != null &&
        remoteAppUserId != user.id;

    final globalOwnerUid = rootClaim?['globalOwnerUid']?.toString();
    final portfolioClaimedByCurrentUser = linkedPortfolioUid != null &&
        globalOwnerUid != null &&
        globalOwnerUid == linkedPortfolioUid;
    final portfolioClaimedByOther =
        globalOwnerUid != null && !portfolioClaimedByCurrentUser;

    return ColorClaimStatus(
      hex: hex,
      hexId: hexId,
      transClaimedByOther: transClaimedByOther || remoteAppOwnedByOther,
      transClaimedByCurrentUser: transClaimedByCurrentUser,
      transOwnerLabel: localOwnerLabel ?? appClaim?['ownerLabel']?.toString(),
      transOwnerUserId: localOwnerUserId ?? remoteAppUserId,
      portfolioClaimedByOther: portfolioClaimedByOther,
      portfolioClaimedByCurrentUser: portfolioClaimedByCurrentUser,
      portfolioOwnerLabel: rootClaim?['globalOwnerLabel']?.toString(),
      portfolioOwnerUid: globalOwnerUid,
      portfolioStatusChecked: remote != null,
    );
  }

  static Future<ColorClaimResult> claimColor(
    Color color, {
    Map<String, dynamic>? currentProfile,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      throw const ColorClaimException(
          'You need to be signed in to save a theme color.');
    }

    final hex = normalizeColor(color);
    final hexId = hexIdFromHex(hex);
    final now = DateTime.now().toUtc().toIso8601String();
    final profile = currentProfile ?? await SupabaseService.getCurrentProfile();
    final linkedPortfolioUid = _extractLinkedPortfolioUid(profile);
    final ownerLabel = _ownerLabelFor(profile, user);

    final existing = await _getLocalClaim(hexId);
    final existingOwnerUserId = existing?['external_user_id']?.toString();
    if (existing != null &&
        existingOwnerUserId != null &&
        existingOwnerUserId != user.id) {
      throw ColorClaimException(
        'That color is already claimed in Trans by ${existing['owner_label'] ?? 'another user'}.',
      );
    }

    await SupabaseService.client
        .from(_claimsTable)
        .update({
          'active': false,
          'released_at': now,
          'updated_at': now,
        })
        .eq('external_user_id', user.id)
        .eq('active', true)
        .neq('hex_id', hexId);

    await SupabaseService.client.from(_claimsTable).upsert({
      'hex_id': hexId,
      'hex': hex,
      'app_id': appId,
      'active': true,
      'external_user_id': user.id,
      'linked_portfolio_uid': linkedPortfolioUid,
      'owner_label': ownerLabel,
      'claimed_at': existing?['claimed_at'] ?? now,
      'last_active_at': now,
      'released_at': null,
      'updated_at': now,
      'sync_state': 'pending',
      'sync_error': null,
    });

    final syncResponse = await _syncToPortfolio(
      hex: hex,
      hexId: hexId,
      externalUserId: user.id,
      linkedPortfolioUid: linkedPortfolioUid,
      ownerLabel: ownerLabel,
      claimedAt: existing?['claimed_at']?.toString() ?? now,
      lastActiveAt: now,
    );

    final syncState = syncResponse?.synced == true
        ? 'synced'
        : (syncResponse?.attempted == true ? 'pending' : 'not_configured');

    await SupabaseService.client.from(_claimsTable).update({
      'linked_portfolio_uid': linkedPortfolioUid,
      'last_active_at': now,
      'updated_at': now,
      'synced_at': syncResponse?.synced == true ? now : null,
      'sync_state': syncState,
      'sync_error': syncResponse?.error,
    }).eq('hex_id', hexId);

    await SupabaseService.updateSettings({
      _settingsClaimKey: {
        'app_id': appId,
        'hex': hex,
        'hex_id': hexId,
        'external_user_id': user.id,
        'linked_portfolio_uid': linkedPortfolioUid,
        'owner_label': ownerLabel,
        'claimed_at': existing?['claimed_at'] ?? now,
        'last_active_at': now,
        'sync_state': syncState,
        'sync_error': syncResponse?.error,
      },
      'theme_color_hex': hex,
    });

    return ColorClaimResult(
      hex: hex,
      hexId: hexId,
      syncedToPortfolio: syncResponse?.synced == true,
      attemptedPortfolioSync: syncResponse?.attempted == true,
      syncMessage: syncResponse?.error,
    );
  }

  static Future<Map<String, dynamic>?> _getLocalClaim(String hexId) async {
    try {
      final row = await SupabaseService.client
          .from(_claimsTable)
          .select()
          .eq('hex_id', hexId)
          .eq('active', true)
          .maybeSingle();
      return _asMap(row);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchPortfolioStatus({
    required String hex,
    required String hexId,
    required String externalUserId,
    required String? linkedPortfolioUid,
  }) async {
    final endpoint = AppConfig.portfolioColorStatusEndpoint;
    if (endpoint.isEmpty) return null;

    try {
      final session = SupabaseService.client.auth.currentSession;
      final uri = Uri.parse(endpoint).replace(
        queryParameters: <String, String>{
          'appId': appId,
          'hex': hex,
          'hexId': hexId,
          'externalUserId': externalUserId,
          if (linkedPortfolioUid != null && linkedPortfolioUid.isNotEmpty)
            'linkedPortfolioUid': linkedPortfolioUid,
        },
      );
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (session?.accessToken != null)
            'Authorization': 'Bearer ${session!.accessToken}',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return _asMap(json.decode(response.body));
    } catch (_) {
      return null;
    }
  }

  static Future<_PortfolioSyncResponse?> _syncToPortfolio({
    required String hex,
    required String hexId,
    required String externalUserId,
    required String? linkedPortfolioUid,
    required String ownerLabel,
    required String claimedAt,
    required String lastActiveAt,
  }) async {
    final endpoint = AppConfig.portfolioColorSyncEndpoint;
    if (endpoint.isEmpty) return null;

    try {
      final session = SupabaseService.client.auth.currentSession;
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (session?.accessToken != null)
            'Authorization': 'Bearer ${session!.accessToken}',
        },
        body: json.encode({
          'appId': appId,
          'hex': hex,
          'hexId': hexId,
          'appClaim': {
            'active': true,
            'appId': appId,
            'hex': hex,
            'externalUserId': externalUserId,
            'linkedPortfolioUid': linkedPortfolioUid,
            'ownerLabel': ownerLabel,
            'claimedAt': claimedAt,
            'lastActiveAt': lastActiveAt,
          },
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _PortfolioSyncResponse(
          attempted: true,
          synced: false,
          error: 'Portfolio sync returned ${response.statusCode}.',
        );
      }

      final payload = _asMap(json.decode(response.body));
      return _PortfolioSyncResponse(
        attempted: true,
        synced: payload?['synced'] != false,
        error: payload?['message']?.toString(),
      );
    } catch (error) {
      return _PortfolioSyncResponse(
        attempted: true,
        synced: false,
        error: error.toString(),
      );
    }
  }

  static String _ownerLabelFor(Map<String, dynamic>? profile, User user) {
    final username = profile?['username']?.toString().trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    final metadataUsername = user.userMetadata?['username']?.toString().trim();
    if (metadataUsername != null && metadataUsername.isNotEmpty) {
      return metadataUsername;
    }
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return user.id;
  }

  static String? _extractLinkedPortfolioUid(Map<String, dynamic>? profile) {
    final settings = _asMap(profile?['settings']);
    final linkedApps = _asMap(settings?['linked_apps']);
    final portfolio = _asMap(linkedApps?['portfolio']);
    final trans = _asMap(linkedApps?['trans']);

    return portfolio?['uid']?.toString() ??
        portfolio?['linked_uid']?.toString() ??
        portfolio?['linkedPortfolioUid']?.toString() ??
        trans?['linkedPortfolioUid']?.toString() ??
        settings?['linked_portfolio_uid']?.toString() ??
        settings?['portfolio_uid']?.toString();
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static bool _isHex(String value) {
    for (final codeUnit in value.codeUnits) {
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      final isLowerHex = codeUnit >= 97 && codeUnit <= 102;
      final isUpperHex = codeUnit >= 65 && codeUnit <= 70;
      if (!isDigit && !isLowerHex && !isUpperHex) {
        return false;
      }
    }
    return true;
  }
}

class _PortfolioSyncResponse {
  final bool attempted;
  final bool synced;
  final String? error;

  const _PortfolioSyncResponse({
    required this.attempted,
    required this.synced,
    required this.error,
  });
}
