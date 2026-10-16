import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChartStyle {
  arc('Arc', Icons.speed_rounded),
  donut('Donut', Icons.donut_large_rounded),
  bar('Bar', Icons.bar_chart_rounded),
  bubbles('Bubbles', Icons.bubble_chart_rounded),
  jar('Jar', Icons.savings_rounded),
  classic('Classic', Icons.view_list_rounded);

  const ChartStyle(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Device-local preferences: theme and the chosen overview chart.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs)
      : _themeMode = ThemeMode.values.asNameMap()[_prefs.getString(_kTheme)] ?? ThemeMode.system,
        _chartStyle = ChartStyle.values.asNameMap()[_prefs.getString(_kChart)] ?? ChartStyle.arc;

  static const _kTheme = 'theme_mode';
  static const _kChart = 'chart_style';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  ChartStyle _chartStyle;

  ThemeMode get themeMode => _themeMode;
  ChartStyle get chartStyle => _chartStyle;

  static Future<SettingsStore> load() async => SettingsStore(await SharedPreferences.getInstance());

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    _prefs.setString(_kTheme, mode.name);
    notifyListeners();
  }

  void setChartStyle(ChartStyle style) {
    if (style == _chartStyle) return;
    _chartStyle = style;
    _prefs.setString(_kChart, style.name);
    notifyListeners();
  }
}
