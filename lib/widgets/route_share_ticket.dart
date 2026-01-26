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
    const backgroundColor = Color(0xFF121212); // Deeper black
    const secondaryBg = Color(0xFF1E1E1E);
    const textColor = Colors.white;
    const secondaryColor = Color(0xFF9E9E9E);
    const accentColor = Colors.blueAccent;

    return Container(
      width: 600,
      color: backgroundColor, // Solid background color for the entire image
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: secondaryBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [secondaryBg, backgroundColor.withOpacity(0.8)],
          ),
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Flare
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          color: accentColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('EEEE, d MMMM').format(journey.departure).toUpperCase(),
                          style: const TextStyle(
                            color: accentColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            DateFormat('HH:mm').format(journey.departure),
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 20),
                          const Icon(Icons.arrow_forward, color: secondaryColor, size: 36),
                          const SizedBox(width: 20),
                          Text(
                            DateFormat('HH:mm').format(journey.arrival),
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green.withOpacity(0.5), width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      FormatUtils.formatDuration(journey.duration.inMinutes),
                      style: const TextStyle(
                        color: Color(0xFF81C784),
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${journey.transferCount} TRANSFERS",
                    style: const TextStyle(
                      color: secondaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildDashedLine(secondaryColor.withOpacity(0.3)),
          const SizedBox(height: 32),
          
          // Steps
          ...journey.steps.map((step) {
            if (step.type == 'wait') return const SizedBox.shrink();
            if (step.type == 'walk' && step.duration.startsWith('0')) return const SizedBox.shrink();
            
            final bool isRide = step.type == 'ride';
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline with Flare
                  Column(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: step.type == 'walk' ? Colors.orange : accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (step.type == 'walk' ? Colors.orange : accentColor).withOpacity(0.4),
                              blurRadius: 8,
                            )
                          ],
                        ),
                      ),
                      if (step != journey.steps.where((s) => s.type != 'wait').last)
                        Container(
                          width: 2,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [secondaryColor.withOpacity(0.3), Colors.transparent],
                            ),
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              step.departureTime,
                              style: const TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(child: _buildStepHeader(step, textColor)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (isRide)
                           Text(
                             "${step.startStationName ?? '?'}  •  ${step.duration}".toUpperCase(),
                             style: const TextStyle(
                               color: secondaryColor,
                               fontSize: 12,
                               fontWeight: FontWeight.bold,
                               letterSpacing: 0.8,
                             ),
                           )
                        else
                           Text(
                             step.instruction,
                             style: const TextStyle(
                               color: secondaryColor,
                               fontSize: 14,
                             ),
                           ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          
          const SizedBox(height: 48),
          _buildDashedLine(secondaryColor.withOpacity(0.3)),
          const SizedBox(height: 24),
          
          // Footer Branding
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Row(
                 children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        'lib/assets/logo.png',
                        width: 24, 
                        height: 24,
                        errorBuilder: (ctx, _, __) => const Icon(Icons.directions_transit, size: 24, color: secondaryColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "TRANS",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                 ],
               ),
               // Pseudo Barcode Flare
               Row(
                 children: List.generate(12, (index) => Container(
                   width: index % 3 == 0 ? 2 : 1,
                   height: 20,
                   margin: const EdgeInsets.only(left: 2),
                   color: secondaryColor.withOpacity(0.3),
                 )),
               ),
            ],
          )
        ],
      ),
    ),
   );
  }

  Widget _buildDashedLine(Color color) {
    return Row(
      children: List.generate(40, (index) => Expanded(
        child: Container(
          height: 1,
          color: index % 2 == 0 ? color : Colors.transparent,
          margin: const EdgeInsets.symmetric(horizontal: 2),
        ),
      )),
    );
  }

  Widget _buildStepHeader(JourneyStep step, Color textColor) {
    if (step.type == 'walk') {
      return Row(
        children: [
          const Icon(Icons.directions_walk, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          const Text(
            "WALK",
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            step.duration,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      );
    }

    if (step.type == 'transfer' || step.type == 'wait') {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              (step.type == 'wait' ? "Wait" : "Transfer").toUpperCase(),
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            step.duration,
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      );
    }

    // Ride Step Logic (Synced with _StepCard)
    String lineName = step.line.trim();
    if (!showTrainNumbers) {
       final regexParens = RegExp(r'\s*\(\d+\)$');
       lineName = lineName.replaceAll(regexParens, '').trim();
       if (step.tripId != null) {
           lineName = lineName.replaceAll(step.tripId!, "").trim();
       }
    }

    final dest = (step.destinationName ?? step.instruction.split('→').last.trim());
    final head = (step.headsign ?? '').trim();
    final isEnd = dest.isNotEmpty && head.isNotEmpty && (head.toLowerCase().contains(dest.toLowerCase()) || dest.toLowerCase().contains(head.toLowerCase()));
    final displayDest = isEnd ? "End of Line" : dest;

    return Row(
      children: [
        Text(
          lineName,
          style: const TextStyle(
            color: Colors.blueAccent,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_right_alt, color: Colors.white, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            displayDest.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
