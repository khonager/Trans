import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Keeps the map marker moving between successive GPS fixes.
class LiveLocationMarker extends StatefulWidget {
  final LatLng position;
  final Widget child;
  final double size;

  const LiveLocationMarker({
    super.key,
    required this.position,
    required this.child,
    this.size = 34,
  });

  @override
  State<LiveLocationMarker> createState() => _LiveLocationMarkerState();
}

class _LiveLocationMarkerState extends State<LiveLocationMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late LatLng _from = widget.position;
  late LatLng _to = widget.position;

  LatLng get _displayed => LatLng(
        _from.latitude + (_to.latitude - _from.latitude) * _controller.value,
        _from.longitude + (_to.longitude - _from.longitude) * _controller.value,
      );

  @override
  void didUpdateWidget(covariant LiveLocationMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position.latitude == oldWidget.position.latitude &&
        widget.position.longitude == oldWidget.position.longitude) {
      return;
    }
    _from = _displayed;
    _to = widget.position;
    // A fresh fix should win over animation when the old point was far away.
    if ((_to.latitude - _from.latitude).abs() > 0.0005 ||
        (_to.longitude - _from.longitude).abs() > 0.0005) {
      _from = _to;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => MarkerLayer(
          markers: [
            Marker(
              point: _displayed,
              width: widget.size,
              height: widget.size,
              child: widget.child,
            ),
          ],
        ),
      );
}
