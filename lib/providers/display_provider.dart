import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DisplayProvider extends ChangeNotifier {
  double _arabicFontSize = 26;
  double _urduFontSize = 13;
  String _arabicFont = 'uthmani';
  double _lineHeight = 1.8;
  double _wordSpacing = 4;

  double get arabicFontSize => _arabicFontSize;
  double get urduFontSize => _urduFontSize;
  String get arabicFont => _arabicFont;
  double get lineHeight => _lineHeight;
  double get wordSpacing => _wordSpacing;

  DisplayProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _arabicFontSize = prefs.getDouble('arabic_size') ?? 26;
    _urduFontSize = prefs.getDouble('urdu_size') ?? 13;
    _arabicFont = prefs.getString('arabic_font') ?? 'uthmani';
    _lineHeight = prefs.getDouble('line_height') ?? 1.8;
    _wordSpacing = prefs.getDouble('word_spacing') ?? 4;
    notifyListeners();
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

  Future<void> setLineHeight(double v) async {
    _lineHeight = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('line_height', v);
  }

  Future<void> setWordSpacing(double v) async {
    _wordSpacing = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('word_spacing', v);
  }
}
