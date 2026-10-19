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

/// The whole app's look. Classic = the original Material design; Futuristic = "Calm Future".
enum UiStyle {
  classic('Classic', Icons.palette_outlined),
  futuristic('Futuristic', Icons.auto_awesome_rounded);

  const UiStyle(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Device-local preferences: app style, theme and the chosen overview chart.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs)
      : _themeMode = ThemeMode.values.asNameMap()[_prefs.getString(_kTheme)] ?? ThemeMode.system,
        _chartStyle = ChartStyle.values.asNameMap()[_prefs.getString(_kChart)] ?? ChartStyle.arc,
        _uiStyle = UiStyle.values.asNameMap()[_prefs.getString(_kUi)] ?? UiStyle.classic;

  static const _kTheme = 'theme_mode';
  static const _kChart = 'chart_style';
  static const _kUi = 'ui_style';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  ChartStyle _chartStyle;
  UiStyle _uiStyle;

  ThemeMode get themeMode => _themeMode;
  ChartStyle get chartStyle => _chartStyle;
  UiStyle get uiStyle => _uiStyle;
  bool get futuristic => _uiStyle == UiStyle.futuristic;

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

  void setUiStyle(UiStyle style) {
    if (style == _uiStyle) return;
    _uiStyle = style;
    _prefs.setString(_kUi, style.name);
    notifyListeners();
  }
}
