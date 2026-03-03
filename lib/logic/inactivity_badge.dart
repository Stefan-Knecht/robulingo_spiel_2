import 'inactivity_badge_stub.dart'
    if (dart.library.io) 'inactivity_badge_io.dart' as impl;

Future<void> initializeInactivityBadgeFeature() =>
    impl.initializeInactivityBadgeFeature();

Future<void> handleInactivityBadgeOnAppResumed() =>
    impl.handleInactivityBadgeOnAppResumed();
