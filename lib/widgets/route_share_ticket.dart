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
    const backgroundColor = Color(0xFF1E1E1E);
    const textColor = Colors.white;
    const secondaryColor = Color(0xFFB0B0B0); // Slightly lighter grey for readability

    return Container(
      width: 600,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM').format(journey.departure),
                      style: const TextStyle(
                        color: secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            DateFormat('HH:mm').format(journey.departure),
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.arrow_forward, color: secondaryColor, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('HH:mm').format(journey.arrival),
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  FormatUtils.formatDuration(journey.duration.inMinutes),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF4CAF50), // Brighter green for dark theme
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white12, thickness: 1),
          const SizedBox(height: 32),
          
          // Steps
          ...journey.steps.map((step) {
            if (step.type == 'wait') return const SizedBox.shrink();
            if (step.type == 'walk' && step.duration.startsWith('0')) return const SizedBox.shrink();
            
            final bool isRide = step.type == 'ride';
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline
                  Column(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: step.type == 'walk' ? Colors.orange : Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: textColor, width: 2.5),
                        ),
                      ),
                      if (step != journey.steps.last)
                        Container(
                          width: 2.5,
                          height: 50,
                          color: Colors.white12,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                    ],
                  ),
                  const SizedBox(width: 20),
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
                                color: secondaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildStepHeader(step, textColor)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Subtext: Start Station • Duration (Matches app)
                        if (isRide)
                           Text(
                             "${step.startStationName ?? '?'}  •  ${step.duration}",
                             style: const TextStyle(
                               color: secondaryColor,
                               fontSize: 14,
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
          
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, thickness: 1),
          const SizedBox(height: 24),
          
          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               // Fixed asset path and visibility
               ClipRRect(
                 borderRadius: BorderRadius.circular(4),
                 child: Image.asset(
                   'assets/logo.png', // Standard asset path
                   width: 20, 
                   height: 20,
                   errorBuilder: (ctx, _, __) => const Icon(Icons.directions_transit, size: 20, color: secondaryColor),
                 ),
               ),
               const SizedBox(width: 8),
               Text(
                 "Shared via Trans",
                 style: TextStyle(color: secondaryColor, fontSize: 13, fontWeight: FontWeight.w500),
               )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStepHeader(JourneyStep step, Color textColor) {
    if (step.type == 'walk') {
      return Row(
        children: [
          const Icon(Icons.directions_walk, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          const Text(
            "Walk",
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 16,
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
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              step.type == 'wait' ? "Wait" : "Transfer",
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.arrow_right_alt, color: Colors.white70, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            displayDest,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }
}
