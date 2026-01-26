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
    // We use a light theme for the ticket to ensure it looks good when shared
    // or dark if we want to match the app. Let's go with a neutral darkish theme
    // similar to the app but valid as a standalone image.
    const backgroundColor = Color(0xFF1E1E1E);
    const cardColor = Color(0xFF2C2C2C);
    const textColor = Colors.white;
    const secondaryColor = Colors.grey;

    return Container(
      width: 600, // Fixed width for the image - increased to prevent overflow
      padding: const EdgeInsets.all(24),
      color: backgroundColor,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            DateFormat('HH:mm').format(journey.departure),
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, color: secondaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('HH:mm').format(journey.arrival),
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 24,
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  FormatUtils.formatDuration(journey.duration.inMinutes),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24),
          const SizedBox(height: 24),
          
          // Steps
          ...journey.steps.map((step) {
            if (step.type == 'walk' && step.duration.startsWith('0')) return const SizedBox.shrink();
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline
                  Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: step.type == 'walk' ? Colors.orange : Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: textColor, width: 2),
                        ),
                      ),
                      if (step != journey.steps.last)
                        Container(
                          width: 2,
                          height: 40,
                          color: Colors.white24,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
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
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _buildStepHeader(step, textColor)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          step.instruction,
                          style: const TextStyle(
                            color: secondaryColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          
          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Icon(Icons.directions_transit, size: 16, color: secondaryColor),
               const SizedBox(width: 8),
               Text(
                 "Shared via Trans",
                 style: TextStyle(color: secondaryColor, fontSize: 12),
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
          const Icon(Icons.directions_walk, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          const Text(
            "Walk",
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            step.duration,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      );
    }

    String lineName = step.line.trim();
    if (!showTrainNumbers) {
       final regexParens = RegExp(r'\s*\(\d+\)$');
       lineName = lineName.replaceAll(regexParens, '').trim();
       if (step.tripId != null) {
           lineName = lineName.replaceAll(step.tripId!, "").trim();
       }
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            lineName,
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            step.headsign ?? step.destinationName ?? "Destination",
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
