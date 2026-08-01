import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DisplayProvider extends ChangeNotifier {
  double _arabicFontSize = 26;
  double _urduFontSize = 13;
  String _arabicFont = 'uthmani';
  bool _grammarColorEnabled = true; //<<<<<<<<<<<<<<<<<

  double get arabicFontSize => _arabicFontSize;
  double get urduFontSize => _urduFontSize;
  String get arabicFont => _arabicFont;

  bool get grammarColorEnabled => _grammarColorEnabled; //<<<<<<<<<

  DisplayProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _arabicFontSize = prefs.getDouble('arabic_size') ?? 26;
    _urduFontSize = prefs.getDouble('urdu_size') ?? 13;
    _arabicFont = prefs.getString('arabic_font') ?? 'uthmani';

    _grammarColorEnabled = //<<<<<<<<<<<<<<<<<<
        prefs.getBool('grammar_color_enabled') ?? true; //<<<<<<<<<<
    _enableWordColors = //<<<<<<<<<<<
        prefs.getBool('enable_word_colors') ?? true; //<<<<<<<
    notifyListeners();
  }

  //<<<<<<<<
  bool _enableWordColors = true;
  bool get enableWordColors => _enableWordColors;
  Future<void> setEnableWordColors(bool value) async {
    _enableWordColors = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_word_colors', value);
  }

  Future<void> setArabicSize(double v) async {
    _arabicFontSize = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('arabic_size', v);
  }

  Future<void> setUrduSize(double v) async {
    _urduFontSize = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('urdu_size', v);
  }

  Future<void> setArabicFont(String f) async {
    _arabicFont = f;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('arabic_font', f);
  }

  Future<void> setGrammarColorEnabled(bool v) async {
    _grammarColorEnabled = v;
    notifyListeners();

    final p = await SharedPreferences.getInstance();
    await p.setBool('grammar_color_enabled', v);
  }
}
