import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String _lastOpenedAtEpochMsKey = 'lastOpenedAtEpochMs';
const String _badgeArmedKey = 'badgeArmed';
const String _notificationPermissionAskedKey =
    'badgeNotificationPermissionAsked';

const String _workUniqueName = 'dailywords_inactivity_badge_one_off';
const String _workTaskName = 'dailywords_inactivity_badge_task';

const String _notificationChannelId = 'dailywords_inactivity_badge';
const String _notificationChannelName = 'DailyWords Inactivity Reminder';
const String _notificationChannelDescription =
    'Shows a badge reminder after 1 hour without opening the app.';
const int _badgeNotificationId = 48048;
const Duration _inactivityThreshold = Duration(hours: 1);

@pragma('vm:entry-point')
void _inactivityBadgeCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (!Platform.isAndroid) return true;
    if (task != _workTaskName) return true;
    try {
      await _runInactivityBadgeCheck();
    } catch (error, stackTrace) {
      debugPrint('[badge][worker][error] $error');
      debugPrint('[badge][worker][stack] $stackTrace');
    }
    return true;
  });
}

Future<void> initializeInactivityBadgeFeature() async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().initialize(
      _inactivityBadgeCallbackDispatcher,
    );
    await _ensureNotificationsInitialized();
    await _scheduleInactivityCheck();
  } catch (error, stackTrace) {
    debugPrint('[badge][init][error] $error');
    debugPrint('[badge][init][stack] $stackTrace');
  }
}

Future<void> handleInactivityBadgeOnAppResumed() async {
  if (!Platform.isAndroid) return;
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  try {
    await _ensureNotificationPermissionRequestedOnce();
    await _clearBadgeReminder();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_badgeArmedKey, false);
    await prefs.setInt(_lastOpenedAtEpochMsKey, nowMs);
    await _scheduleInactivityCheck();
  } catch (error, stackTrace) {
    debugPrint('[badge][resume][error] $error');
    debugPrint('[badge][resume][stack] $stackTrace');
  }
}

Future<void> _runInactivityBadgeCheck() async {
  final prefs = await SharedPreferences.getInstance();
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final lastOpenedMs = prefs.getInt(_lastOpenedAtEpochMsKey) ?? nowMs;
  final badgeArmed = prefs.getBool(_badgeArmedKey) ?? false;
  if (badgeArmed) return;
  if ((nowMs - lastOpenedMs) < _inactivityThreshold.inMilliseconds) return;
  await _showBadgeReminder();
  await prefs.setBool(_badgeArmedKey, true);
}

Future<void> _scheduleInactivityCheck() async {
  await Workmanager().registerOneOffTask(
    _workUniqueName,
    _workTaskName,
    initialDelay: _inactivityThreshold,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.notRequired),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );
}

Future<void> _ensureNotificationPermissionRequestedOnce() async {
  final prefs = await SharedPreferences.getInstance();
  final status = await Permission.notification.status;
  if (status == PermissionStatus.granted) return;
  final askedAlready = prefs.getBool(_notificationPermissionAskedKey) ?? false;
  if (askedAlready || status == PermissionStatus.permanentlyDenied) return;
  await prefs.setBool(_notificationPermissionAskedKey, true);
  await Permission.notification.request();
}

Future<FlutterLocalNotificationsPlugin>
    _ensureNotificationsInitialized() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    const channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.low,
      playSound: false,
      showBadge: true,
    );
    await androidPlugin.createNotificationChannel(channel);
  }
  return plugin;
}

Future<void> _showBadgeReminder() async {
  final plugin = await _ensureNotificationsInitialized();
  const androidDetails = AndroidNotificationDetails(
    _notificationChannelId,
    _notificationChannelName,
    channelDescription: _notificationChannelDescription,
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
    onlyAlertOnce: true,
    autoCancel: false,
    showWhen: false,
    number: 1,
    channelShowBadge: true,
  );
  const details = NotificationDetails(android: androidDetails);
  await plugin.show(
    _badgeNotificationId,
    'DailyWords',
    '',
    details,
  );
}

Future<void> _clearBadgeReminder() async {
  final plugin = await _ensureNotificationsInitialized();
  await plugin.cancel(_badgeNotificationId);
}
