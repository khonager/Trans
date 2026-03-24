import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../utils/app_error.dart';

class TransitousLiveMapScreen extends StatefulWidget {
  const TransitousLiveMapScreen({super.key});

  @override
  State<TransitousLiveMapScreen> createState() =>
      _TransitousLiveMapScreenState();
}

class _TransitousLiveMapScreenState extends State<TransitousLiveMapScreen> {
  static final Uri _liveMapUri = Uri.parse('https://api.transitous.org/');

  bool _isOpening = false;

  Future<void> _openLiveMap() async {
    if (_isOpening) return;

    setState(() => _isOpening = true);
    try {
      var opened = await launchUrl(
        _liveMapUri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) {
        opened = await launchUrl(_liveMapUri, mode: LaunchMode.platformDefault);
      }
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't open the Transitous live map."),
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      await AppError.showSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        source: 'transitous live map',
        fallback: "Couldn't open the Transitous live map.",
      );
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = TransColors.of(context);

    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Live Map'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.cardBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colors.navBarSelected.withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            colors.navBarSelected.withValues(alpha: 0.24),
                            colors.navBarSelected.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        Icons.directions_bus_filled_rounded,
                        size: 42,
                        color: colors.navBarSelected,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'You found the live fleet map.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Transitous exposes this through their web interface. '
                      'This easter egg opens the map in an in-app browser when possible.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isOpening ? null : _openLiveMap,
                      icon: _isOpening
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore_rounded),
                      label:
                          Text(_isOpening ? 'Opening...' : 'Open Transitous'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Keep it secret'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
