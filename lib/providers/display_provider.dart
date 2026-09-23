import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DisplayProvider extends ChangeNotifier {
  double _arabicFontSize = 26;
  double _urduFontSize = 13;
  String _arabicFont = 'uthmani';
  bool _grammarColorEnabled = true;
  bool _enableWordColors = true;
  bool _showBismillah = true;
  bool _showWbw = true;
  bool _showAyahTranslation = true;

  // Setters wait for the initial load so it can never overwrite a fresh value.
  late final Future<void> _ready;

  double get arabicFontSize => _arabicFontSize;
  double get urduFontSize => _urduFontSize;
  String get arabicFont => _arabicFont;
  bool get grammarColorEnabled => _grammarColorEnabled;
  bool get enableWordColors => _enableWordColors;
  bool get showBismillah => _showBismillah;
  bool get showWbw => _showWbw;
  bool get showAyahTranslation => _showAyahTranslation;

  DisplayProvider() {
    _ready = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _arabicFontSize = prefs.getDouble('arabic_size') ?? 26;
    _urduFontSize = prefs.getDouble('urdu_size') ?? 13;
    _arabicFont = prefs.getString('arabic_font') ?? 'uthmani';
    _grammarColorEnabled = prefs.getBool('grammar_color_enabled') ?? true;
    _enableWordColors = prefs.getBool('enable_word_colors') ?? true;
    _showBismillah = prefs.getBool('show_bismillah') ?? true;
    _showWbw = prefs.getBool('show_wbw') ?? true;
    _showAyahTranslation = prefs.getBool('show_ayah_translation') ?? true;
    notifyListeners();
  }

  Future<void> _saveBool(String key, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
  }

  Future<void> setShowBismillah(bool v) async {
    await _ready;
    _showBismillah = v;
    notifyListeners();
    await _saveBool('show_bismillah', v);
  }

  Future<void> setShowWbw(bool v) async {
    await _ready;
    _showWbw = v;
    notifyListeners();
    await _saveBool('show_wbw', v);
  }

  Future<void> setShowAyahTranslation(bool v) async {
    await _ready;
    _showAyahTranslation = v;
    notifyListeners();
    await _saveBool('show_ayah_translation', v);
  }

  Future<void> setEnableWordColors(bool value) async {
    await _ready;
    _enableWordColors = value;
    notifyListeners();
    await _saveBool('enable_word_colors', value);
  }

  Future<void> setArabicSize(double v) async {
    await _ready;
    _arabicFontSize = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('arabic_size', v);
  }

  Future<void> setUrduSize(double v) async {
    await _ready;
    _urduFontSize = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('urdu_size', v);
  }

  Future<void> setArabicFont(String f) async {
    await _ready;
    _arabicFont = f;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('arabic_font', f);
  }

  Future<void> setGrammarColorEnabled(bool v) async {
    await _ready;
    _grammarColorEnabled = v;
    notifyListeners();
    await _saveBool('grammar_color_enabled', v);
  }
}