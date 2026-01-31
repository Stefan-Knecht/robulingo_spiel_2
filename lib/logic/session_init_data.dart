import '../data/models.dart';
import 'item_presentation_policy.dart';

class SessionInitData {
  SessionInitData({
    required this.awaitingLang,
    required this.awaitingStart,
    required this.awaitingNative,
    required this.loading,
    required this.error,
    required this.trialIndex,
    required this.currentTrial,
    required this.currentSlot,
    required this.pendingNextSlot,
    required this.lastAnsweredCursorUuid,
    required this.hasAnswered,
    required this.lastCorrect,
    required this.lastSelectionIsLeft,
    required this.micPromptActive,
    required this.micDenied,
    required this.currentTrialAudioToken,
    required this.currentTrialAudioUuid,
    required this.currentTrialAudioUri,
    required this.namingInProgress,
    required this.namingStatus,
    required this.namingDisabled,
    required this.liveTranscript,
    required this.currentTrialToken,
    required this.sessionStart,
    required this.sessionEnded,
    required this.curriculumStartOffset,
  });

  final bool awaitingLang;
  final bool awaitingStart;
  final bool awaitingNative;
  final bool loading;
  final String? error;
  final int trialIndex;
  final Trial? currentTrial;
  final PresentationSlot currentSlot;
  final PresentationSlot? pendingNextSlot;
  final String? lastAnsweredCursorUuid;
  final bool hasAnswered;
  final bool? lastCorrect;
  final bool? lastSelectionIsLeft;
  final bool micPromptActive;
  final bool micDenied;
  final int currentTrialAudioToken;
  final String? currentTrialAudioUuid;
  final Uri? currentTrialAudioUri;
  final bool namingInProgress;
  final String namingStatus;
  final bool namingDisabled;
  final String liveTranscript;
  final int currentTrialToken;
  final DateTime sessionStart;
  final bool sessionEnded;
  final int curriculumStartOffset;
}

SessionInitData buildSessionInitData(DateTime nowUtc) {
  return SessionInitData(
    awaitingLang: false,
    awaitingStart: false,
    awaitingNative: false,
    loading: true,
    error: null,
    trialIndex: 0,
    currentTrial: null,
    currentSlot:
        const PresentationSlot(mode: PresentationMode.comprehension, targetUuid: ''),
    pendingNextSlot: null,
    lastAnsweredCursorUuid: null,
    hasAnswered: false,
    lastCorrect: null,
    lastSelectionIsLeft: null,
    micPromptActive: false,
    micDenied: false,
    currentTrialAudioToken: -1,
    currentTrialAudioUuid: null,
    currentTrialAudioUri: null,
    namingInProgress: false,
    namingStatus: '',
    namingDisabled: false,
    liveTranscript: '',
    currentTrialToken: 0,
    sessionStart: nowUtc,
    sessionEnded: false,
    curriculumStartOffset: 0,
  );
}
