import 'package:trans/models/journey.dart';

enum JointJourneyIntent { fast, balanced, together }

enum SharedJourneyMode { ride, walk, wait }

class JointJourneyPreferences {
  final JointJourneyIntent intent;
  final int maxExtraTravelMinutes;
  final int maxExtraTransfers;

  const JointJourneyPreferences({
    required this.intent,
    required this.maxExtraTravelMinutes,
    required this.maxExtraTransfers,
  });

  const JointJourneyPreferences.fast()
      : this(
          intent: JointJourneyIntent.fast,
          maxExtraTravelMinutes: 10,
          maxExtraTransfers: 1,
        );

  const JointJourneyPreferences.balanced()
      : this(
          intent: JointJourneyIntent.balanced,
          maxExtraTravelMinutes: 20,
          maxExtraTransfers: 2,
        );

  const JointJourneyPreferences.together()
      : this(
          intent: JointJourneyIntent.together,
          maxExtraTravelMinutes: 35,
          maxExtraTransfers: 3,
        );
}

class SharedJourneySegment {
  final SharedJourneyMode mode;
  final DateTime start;
  final DateTime end;
  final String label;

  const SharedJourneySegment({
    required this.mode,
    required this.start,
    required this.end,
    required this.label,
  });

  Duration get duration => end.difference(start);
}

class JointJourneyOption {
  final Journey myJourney;
  final Journey friendJourney;
  final List<SharedJourneySegment> sharedSegments;
  final Duration sharedDuration;
  final Duration sharedRideDuration;
  final Duration sharedWalkDuration;
  final Duration sharedWaitDuration;
  final int myExtraMinutes;
  final int friendExtraMinutes;
  final int myExtraTransfers;
  final int friendExtraTransfers;
  final double score;

  const JointJourneyOption({
    required this.myJourney,
    required this.friendJourney,
    required this.sharedSegments,
    required this.sharedDuration,
    required this.sharedRideDuration,
    required this.sharedWalkDuration,
    required this.sharedWaitDuration,
    required this.myExtraMinutes,
    required this.friendExtraMinutes,
    required this.myExtraTransfers,
    required this.friendExtraTransfers,
    required this.score,
  });
}
