import 'package:flutter/material.dart';

import 'main_native.dart' if (dart.library.js_interop) 'main_web.dart'
    as platform;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await platform.createApp());
}
