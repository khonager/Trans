import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trans/models/journey.dart';
import 'package:trans/utils/format_utils.dart';

class RouteShareTicket extends StatelessWidget {
  final Journey journey;
  final bool showTrainNumbers;

  const RouteShareTicket({
    super.key,
    required this.journey,
    this.showTrainNumbers = false,
  });

  @override
  Widget build(BuildContext context) {
    const outerBg = Color(0xFF0F0F0F); // True black for outer edges
    const ticketBg = Color(0xFF1A1A1A); // Slightly lighter for ticket body
    const accentColor = Colors.blueAccent;
    const textColor = Colors.white;
    const secondaryColor = Color(0xFFA0A0A0);
    const monospaceFont = 'monospace'; // Use default monospace

    return Container(
      width: 600,
      color: outerBg, // Solid background
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Upper Ticket Part
          Container(
            padding: const EdgeInsets.all(40),
            decoration: const BoxDecoration(
              color: ticketBg,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF252525), ticketBg],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Branding
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.asset('lib/assets/logo.png', width: 20, height: 20, errorBuilder: (_, __, ___) => const Icon(Icons.train, size: 20, color: accentColor)),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "TRANSIT BOARDING PASS",
                          style: TextStyle(color: accentColor, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2.0),
                        ),
                      ],
                    ),
                    Text(
                      DateFormat('MM/dd/yyyy').format(journey.departure),
                      style: const TextStyle(color: secondaryColor, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: monospaceFont),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Times
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("DEP", style: TextStyle(color: secondaryColor, fontSize: 10, fontWeight: FontWeight.w900)),
                        Text(
                          DateFormat('HH:mm').format(journey.departure),
                          style: const TextStyle(color: textColor, fontSize: 48, fontWeight: FontWeight.w900, fontFamily: monospaceFont),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Icon(Icons.arrow_forward, color: secondaryColor, size: 24),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text("ARR", style: TextStyle(color: secondaryColor, fontSize: 10, fontWeight: FontWeight.w900)),
                        Text(
                          DateFormat('HH:mm').format(journey.arrival),
                          style: const TextStyle(color: textColor, fontSize: 48, fontWeight: FontWeight.w900, fontFamily: monospaceFont),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ),
              ],
            ),
          ),

          // Perforated Divider
          _buildPerforatedDivider(outerBg),

          // Lower Ticket Part (Dense Steps)
          Container(
            padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
            color: ticketBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...journey.steps.where((s) => s.type != 'wait').map((step) {
                  final bool isRide = step.type == 'ride';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.departureTime,
                          style: const TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 16, fontFamily: monospaceFont),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStepHeaderDense(step, textColor),
                              const SizedBox(height: 4),
                              Text(
                                isRide ? "${step.startStationName ?? '?'} • ${step.duration}".toUpperCase() : step.instruction,
                                style: const TextStyle(color: secondaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                // Trip Detail Bar removed, now putting duration in footer or before barcode
                Center(
                  child: Text(
                    FormatUtils.formatDuration(journey.duration.inMinutes).toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF81C784), // Premium green
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      fontFamily: monospaceFont,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("SYSTEM_ID", style: TextStyle(color: secondaryColor.withOpacity(0.5), fontSize: 8, fontWeight: FontWeight.bold)),
                        Text(journey.source.toUpperCase(), style: const TextStyle(color: secondaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      children: List.generate(24, (index) => Container(
                        width: index % 4 == 0 ? 3 : 1,
                        height: 30,
                        margin: const EdgeInsets.only(left: 2),
                        color: secondaryColor.withOpacity(0.4),
                      )),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketInfo(String label, String value, {bool monospace = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 8, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, fontFamily: monospace ? 'monospace' : null)),
      ],
    );
  }

  Widget _buildPerforatedDivider(Color cutoutColor) {
    return Container(
      color: const Color(0xFF1A1A1A),
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: List.generate(40, (i) => Expanded(
              child: Container(height: 1.5, color: i % 2 == 0 ? Colors.white24 : Colors.transparent, margin: const EdgeInsets.symmetric(horizontal: 2)),
            )),
          ),
          Positioned(left: -15, child: Container(width: 30, height: 30, decoration: BoxDecoration(color: cutoutColor, shape: BoxShape.circle))),
          Positioned(right: -15, child: Container(width: 30, height: 30, decoration: BoxDecoration(color: cutoutColor, shape: BoxShape.circle))),
        ],
      ),
    );
  }

  Widget _buildStepHeaderDense(JourneyStep step, Color textColor) {
    if (step.type == 'walk') {
      return Row(
        children: [
          const Icon(Icons.directions_walk, size: 14, color: Colors.orange),
          const SizedBox(width: 8),
          const Text("WALK", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(width: 8),
          Text(step.duration, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      );
    }

    if (step.type == 'transfer') {
       return Row(
        children: [
          const Icon(Icons.sync, size: 14, color: Colors.blueAccent),
          const SizedBox(width: 8),
          const Text("TRANSFER", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(width: 8),
          Text(step.duration, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      );
    }

    String lineName = step.line.trim();
    if (!showTrainNumbers) {
       lineName = lineName.replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim();
       if (step.tripId != null) lineName = lineName.replaceAll(step.tripId!, "").trim();
    }

    final dest = (step.destinationName ?? step.instruction.split('→').last.trim());
    final head = (step.headsign ?? '').trim();
    final isEnd = dest.isNotEmpty && head.isNotEmpty && (head.toLowerCase().contains(dest.toLowerCase()) || dest.toLowerCase().contains(head.toLowerCase()));
    final displayDest = isEnd ? "End of Line" : dest;

    return Row(
      children: [
        Text(lineName, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_right_alt, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(displayDest.toUpperCase(), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
      ],
    );
  }
}
