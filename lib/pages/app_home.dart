import 'package:flutter/widgets.dart';
import 'package:unidrop/providers/settings_provider.dart';
import 'package:unidrop/pages/app_home_io.dart'
    if (dart.library.html) 'package:unidrop/pages/app_home_web.dart' as impl;

Widget buildAppHome(SettingsState settings) {
  return impl.buildAppHome(settings);
}
