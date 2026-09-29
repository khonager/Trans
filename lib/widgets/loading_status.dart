import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trans/l10n/app_localizations.dart';

/// A status tied to the current operation. The secondary message only says
/// that the same operation is taking longer; it never claims a new step began.
class LoadingStatus extends StatefulWidget {
  const LoadingStatus({
    super.key,
    required this.message,
    this.compact = false,
    this.color,
  });

  final String message;
  final bool compact;
  final Color? color;

  @override
  State<LoadingStatus> createState() => _LoadingStatusState();
}

class _LoadingStatusState extends State<LoadingStatus> {
  Timer? _timer;
  bool _takingLonger = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _takingLonger = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.color ?? theme.colorScheme.onSurface;
    return Semantics(
      liveRegion: true,
      label: widget.message,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: widget.compact ? 16 : 24,
                height: widget.compact ? 16 : 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.message,
                  style: (widget.compact
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(color: color),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          if (_takingLonger) ...[
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.stillWaitingForResults,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
