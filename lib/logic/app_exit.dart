import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> exitApp({
  required BuildContext context,
  required VoidCallback onReturnToStart,
}) async {
  if (kIsWeb) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    onReturnToStart();
    return;
  }
  if (Platform.isIOS) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    onReturnToStart();
    return;
  }
  if (Platform.isAndroid) {
    SystemNavigator.pop();
    return;
  }
  exit(0);
}
