// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import '../providers/display_provider.dart';
import '../providers/user_provider.dart';
import '../services/word_glossary_service.dart';
import '../services/translation_service.dart';

class OnboardingScreen extends StatefulWidget {
  final Widget child; // Home screen shown after completion
  const OnboardingScreen({super.key, required this.child});

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('onboarding_complete') ?? false);
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF2D6A4F);
  static const _cream = Color(0xFFFDF8F0);

  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  bool _done = false;

  // Selections
  String _themeChoice = 'system';
  String _arabicFont = 'noorehuda';
  String _translationLang = 'ur';
  String _wbwLang = 'ur';
  int _dailyGoal = 10;
  bool _showBismillah = true;
  bool _showWbw = true;
  bool _showAyahTranslation = true;
  bool _mushafMode = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const int _totalPages = 8;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_currentPage < _totalPages - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  void _skip() {
    HapticFeedback.lightImpact();
    _pageCtrl.animateToPage(_totalPages - 1,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  Future<void> _finish() async {
    await _applyAllSettings();
    await OnboardingScreen.markComplete();
    if (mounted) setState(() => _done = true);
  }

  Future<void> _applyAllSettings() async {
    final theme = context.read<ThemeProvider>();
    final display = context.read<DisplayProvider>();
    final user = context.read<UserProvider>();
    final prefs = await SharedPreferences.getInstance();

    // Theme
    if (_themeChoice == 'dark') {
      if (!theme.isDark) theme.toggleTheme();
    } else if (_themeChoice == 'light') {
      if (theme.isDark) theme.toggleTheme();
    }
    await prefs.setString('theme_mode', _themeChoice);

    // Arabic font
    await display.setArabicFont(_arabicFont);

    // WBW language
    await WordGlossaryService.setLanguage(_wbwLang);

    // Translation language
    final scholarKey = _translationLang == 'en'
        ? 'khan'
        : _translationLang == 'hi'
            ? 'hindi'
            : 'fateh';
    await TranslationService.setScholar(scholarKey);

    // Daily goal
    await user.updateProfile({'dailyGoal': _dailyGoal});

    // Reading preferences
    await prefs.setBool('show_bismillah', _showBismillah);
    await prefs.setBool('show_wbw', _showWbw);
    await prefs.setBool('show_ayah_translation', _showAyahTranslation);
    await prefs.setBool('mushaf_mode_default', _mushafMode);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A1628) : _cream,
        body: SafeArea(
          child: Column(
            children: [
              // Top bar — progress + skip
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    // Progress dots
                    Row(
                      children: List.generate(_totalPages, (i) {
                        final active = i == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 6),
                          width: active ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? _gold
                                : (isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const Spacer(),
                    // Skip button (hidden on last page)
                    if (_currentPage < _totalPages - 1)
                      GestureDetector(
                        onTap: _skip,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300),
                          ),
                          child: Text('Skip',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey.shade500)),
                        ),
                      ),
                  ],
                ),
              ),

              // Pages
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _WelcomePage(isDark: isDark),
                    _ThemePage(
                      isDark: isDark,
                      selected: _themeChoice,
                      onSelect: (v) => setState(() => _themeChoice = v),
                    ),
                    _FontPage(
                      isDark: isDark,
                      selected: _arabicFont,
                      onSelect: (v) => setState(() => _arabicFont = v),
                    ),
                    _TranslationPage(
                      isDark: isDark,
                      selected: _translationLang,
                      onSelect: (v) => setState(() => _translationLang = v),
                    ),
                    _WbwPage(
                      isDark: isDark,
                      selected: _wbwLang,
                      onSelect: (v) => setState(() => _wbwLang = v),
                    ),
                    _GoalPage(
                      isDark: isDark,
                      selected: _dailyGoal,
                      onSelect: (v) => setState(() => _dailyGoal = v),
                    ),
                    _ReadingPrefsPage(
                      isDark: isDark,
                      showBismillah: _showBismillah,
                      showWbw: _showWbw,
                      showAyahTranslation: _showAyahTranslation,
                      onBismillah: (v) => setState(() => _showBismillah = v),
                      onWbw: (v) => setState(() => _showWbw = v),
                      onAyahTranslation: (v) =>
                          setState(() => _showAyahTranslation = v),
                    ),
                    _FinishPage(
                      isDark: isDark,
                      themeChoice: _themeChoice,
                      arabicFont: _arabicFont,
                      translationLang: _translationLang,
                      wbwLang: _wbwLang,
                      dailyGoal: _dailyGoal,
                    ),
                  ],
                ),
              ),

              // Back + Next buttons
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  children: [
                    // Back button — hidden on first page
                    if (_currentPage > 0)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _pageCtrl.previousPage(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeInOut);
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300),
                            color: isDark
                                ? const Color(0xFF1A2E1F)
                                : Colors.white,
                          ),
                          child: Icon(Icons.arrow_back,
                              color: isDark ? Colors.white70 : _green),
                        ),
                      ),
                    // Next / Start button
                    Expanded(
                      child: GestureDetector(
                        onTap: _next,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [_green, _teal],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _green.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _currentPage == _totalPages - 1
                                  ? 'Start Learning'
                                  : 'Continue',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Page base widget ──────────────────────────────────────────────────────────
class _PageBase extends StatelessWidget {
  final bool isDark;
  final String emoji;
  final String title;
  final String subtitle;
  final Widget content;

  const _PageBase({
    required this.isDark,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1B4332),
                height: 1.2,
              )),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
                height: 1.5,
              )),
          const SizedBox(height: 28),
          content,
        ],
      ),
    );
  }
}

// ── Page 1: Welcome ───────────────────────────────────────────────────────────
class _WelcomePage extends StatelessWidget {
  final bool isDark;
  const _WelcomePage({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Bismillah display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1B4332), const Color(0xFF0D2B1E)]
                    : [const Color(0xFFF0F7F0), const Color(0xFFE8F3E8)],
              ),
              border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Text(
                  '﷽',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 36,
                    color: const Color(0xFFD4AF37),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.amiriQuran(
                    fontSize: 22,
                    color: isDark ? Colors.white : const Color(0xFF1B4332),
                    height: 2.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Quran Kalima',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1B4332),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'کلمۂ قرآن',
            style: TextStyle(
              fontSize: 20,
              color: const Color(0xFFD4AF37),
            ),
          ),
          const SizedBox(height: 20),
          // Feature chips
          ...[
            ('📖', 'Read the Quran word by word'),
            ('🃏', 'Learn vocabulary with flashcards'),
            ('📊', 'Track your progress daily'),
            ('☁️', 'Sync across all your devices'),
          ].map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B4332).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFD4AF37)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Center(
                          child: Text(item.$1,
                              style: const TextStyle(fontSize: 20))),
                    ),
                    const SizedBox(width: 14),
                    Text(item.$2,
                        style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white70 : Colors.black87)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Text(
            'Let\'s take 60 seconds to personalise your experience.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 2: Theme ─────────────────────────────────────────────────────────────
class _ThemePage extends StatelessWidget {
  final bool isDark;
  final String selected;
  final Function(String) onSelect;
  const _ThemePage(
      {required this.isDark, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _PageBase(
      isDark: isDark,
      emoji: '🎨',
      title: 'Choose\nyour theme',
      subtitle: 'You can change this anytime from Settings.',
      content: Column(
        children: [
          _themeCard('light', '☀️', 'Light', 'Clean and bright',
              const Color(0xFFFDF8F0), const Color(0xFF1B4332)),
          const SizedBox(height: 12),
          _themeCard('dark', '🌙', 'Dark', 'Easy on the eyes',
              const Color(0xFF0A1628), Colors.white),
          const SizedBox(height: 12),
          _themeCard('system', '📱', 'Follow System',
              'Matches your phone setting', Colors.grey.shade200, Colors.black),
        ],
      ),
    );
  }

  Widget _themeCard(String key, String emoji, String label, String sublabel,
      Color bg, Color fg) {
    final sel = selected == key;
    return GestureDetector(
      onTap: () => onSelect(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? const Color(0xFFD4AF37) : Colors.grey.shade300,
            width: sel ? 2 : 1,
          ),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                      blurRadius: 12)
                ]
              : [],
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: fg)),
              Text(sublabel,
                  style: TextStyle(
                      fontSize: 12, color: fg.withValues(alpha: 0.6))),
            ]),
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sel ? const Color(0xFFD4AF37) : Colors.transparent,
                border: Border.all(
                  color: sel ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: sel
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 3: Arabic Font ───────────────────────────────────────────────────────
class _FontPage extends StatelessWidget {
  final bool isDark;
  final String selected;
  final Function(String) onSelect;
  const _FontPage(
      {required this.isDark, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _PageBase(
      isDark: isDark,
      emoji: '🕌',
      title: 'Arabic\nfont style',
      subtitle: 'Choose the font that feels most natural to read.',
      content: Column(
        children: [
          _fontCard(context, 'noorehuda', 'Noorehuda',
              'Traditional Indo-Pak style', 'NoorehudaFont'),
          const SizedBox(height: 12),
          _fontCard(context, 'uthmani', 'Uthmani',
              'Standard Madina Mushaf font', null),
          const SizedBox(height: 12),
          _fontCard(context, 'indopak', 'Indo-Pak',
              'Regional Urdu-script style', 'IndoPak'),
        ],
      ),
    );
  }

  Widget _fontCard(BuildContext context, String key, String label,
      String sublabel, String? fontFamily) {
    final sel = selected == key;
    final isDarkLocal = Theme.of(context).brightness == Brightness.dark;
    TextStyle arabicStyle;
    if (fontFamily != null) {
      arabicStyle = TextStyle(
          fontFamily: fontFamily,
          fontSize: 22,
          color: isDarkLocal ? Colors.white : const Color(0xFF1B4332),
          height: 2.0);
    } else {
      arabicStyle = GoogleFonts.amiriQuran(
          fontSize: 22,
          color: isDarkLocal ? Colors.white : const Color(0xFF1B4332),
          height: 2.0);
    }

    return GestureDetector(
      onTap: () => onSelect(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkLocal ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? const Color(0xFFD4AF37) : Colors.grey.shade300,
            width: sel ? 2 : 1,
          ),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                      blurRadius: 12)
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDarkLocal ? Colors.white : Colors.black87)),
                  Text(sublabel,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDarkLocal
                              ? Colors.white54
                              : Colors.grey.shade500)),
                ]),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sel ? const Color(0xFFD4AF37) : Colors.transparent,
                    border: Border.all(
                      color: sel
                          ? const Color(0xFFD4AF37)
                          : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: sel
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
                textDirection: TextDirection.rtl, style: arabicStyle),
          ],
        ),
      ),
    );
  }
}

// ── Page 4: Translation Language ─────────────────────────────────────────────
class _TranslationPage extends StatelessWidget {
  final bool isDark;
  final String selected;
  final Function(String) onSelect;
  const _TranslationPage(
      {required this.isDark, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _PageBase(
      isDark: isDark,
      emoji: '🌍',
      title: 'Ayah\ntranslation',
      subtitle: 'Which language for the full ayah translation?',
      content: Column(
        children: [
          _langCard('ur', '🇵🇰', 'Urdu', 'اردو', 'Fateh Muhammad Jalandhri'),
          const SizedBox(height: 12),
          _langCard('en', '🇬🇧', 'English', 'English', 'Mufti Taqi Usmani'),
          const SizedBox(height: 12),
          _langCard('hi', '🇮🇳', 'Hindi', 'हिंदी', 'Hindi Translation'),
        ],
      ),
    );
  }

  Widget _langCard(String key, String flag, String label, String native,
      String scholar) {
    final sel = selected == key;
    return GestureDetector(
      onTap: () => onSelect(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? const Color(0xFFD4AF37) : Colors.grey.shade300,
            width: sel ? 2 : 1,
          ),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                      blurRadius: 12)
                ]
              : [],
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(width: 8),
                Text(native,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.grey.shade600)),
              ]),
              Text(scholar,
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Colors.white38 : Colors.grey.shade500)),
            ]),
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sel ? const Color(0xFFD4AF37) : Colors.transparent,
                border: Border.all(
                  color:
                      sel ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: sel
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 5: Word-by-Word ──────────────────────────────────────────────────────
class _WbwPage extends StatelessWidget {
  final bool isDark;
  final String selected;
  final Function(String) onSelect;
  const _WbwPage(
      {required this.isDark, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _PageBase(
      isDark: isDark,
      emoji: '🔤',
      title: 'Word-by-word\ntranslation',
      subtitle:
          'Each Arabic word will show its meaning below it while reading.',
      content: Column(
        children: [
          _wbwCard('ur', '🇵🇰', 'Urdu', 'اردو — under each word'),
          const SizedBox(height: 12),
          _wbwCard('en', '🇬🇧', 'English', 'English — under each word'),
          const SizedBox(height: 12),
          _wbwCard('hi', '🇮🇳', 'Hindi', 'हिंदी — under each word'),
          const SizedBox(height: 12),
          _wbwCard('off', '🚫', 'Off', 'Show Arabic only'),
        ],
      ),
    );
  }

  Widget _wbwCard(String key, String flag, String label, String sublabel) {
    final sel = selected == key;
    return GestureDetector(
      onTap: () => onSelect(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? const Color(0xFFD4AF37) : Colors.grey.shade300,
            width: sel ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87)),
              Text(sublabel,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.grey.shade500)),
            ]),
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sel ? const Color(0xFFD4AF37) : Colors.transparent,
                border: Border.all(
                  color:
                      sel ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: sel
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 6: Daily Goal ────────────────────────────────────────────────────────
class _GoalPage extends StatelessWidget {
  final bool isDark;
  final int selected;
  final Function(int) onSelect;
  const _GoalPage(
      {required this.isDark, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _PageBase(
      isDark: isDark,
      emoji: '🎯',
      title: 'Daily\nvocabulary goal',
      subtitle:
          '5 words/day = 1,825 words in a year. Consistency beats speed.',
      content: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [5, 10, 15, 20, 30, 50].map((goal) {
              final sel = selected == goal;
              return GestureDetector(
                onTap: () => onSelect(goal),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 100,
                  height: 80,
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF1B4332)
                        : (isDark
                            ? const Color(0xFF1A2E1F)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel
                          ? const Color(0xFFD4AF37)
                          : Colors.grey.shade300,
                      width: sel ? 2 : 1,
                    ),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: const Color(0xFF1B4332)
                                    .withValues(alpha: 0.3),
                                blurRadius: 12)
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$goal',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: sel
                                  ? const Color(0xFFD4AF37)
                                  : (isDark ? Colors.white : Colors.black87))),
                      Text('words/day',
                          style: TextStyle(
                              fontSize: 10,
                              color: sel
                                  ? Colors.white70
                                  : (isDark
                                      ? Colors.white54
                                      : Colors.grey.shade500))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline,
                    color: Color(0xFFD4AF37), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You selected $selected words/day — '
                    '${(selected * 365 / 1000).toStringAsFixed(1)}K words in a year!',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFD4AF37)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 7: Reading Preferences ───────────────────────────────────────────────
class _ReadingPrefsPage extends StatelessWidget {
  final bool isDark;
  final bool showBismillah;
  final bool showWbw;
  final bool showAyahTranslation;
  // final bool mushafMode;
  final Function(bool) onBismillah;
  final Function(bool) onWbw;
  final Function(bool) onAyahTranslation;
  // final Function(bool) onMushaf;

  const _ReadingPrefsPage({
    required this.isDark,
    required this.showBismillah,
    required this.showWbw,
    required this.showAyahTranslation,
    // required this.mushafMode,
    required this.onBismillah,
    required this.onWbw,
    required this.onAyahTranslation,
    // required this.onMushaf,
  });

  @override
  Widget build(BuildContext context) {
    return _PageBase(
      isDark: isDark,
      emoji: '📖',
      title: 'Reading\npreferences',
      subtitle: 'Customise how the Quran appears while you read.',
      content: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            _prefTile('Show Bismillah header',
                'Display بسم الله before each surah', showBismillah,
                onBismillah, isDark, true),
            _divider(),
            _prefTile('Word-by-word translation',
                'Show meaning under each Arabic word', showWbw, onWbw, isDark,
                false),
            _divider(),
            _prefTile('Ayah translation',
                'Show full ayah translation below', showAyahTranslation,
                onAyahTranslation, isDark, false),
            // _divider(),
            // _prefTile('Mushaf mode',
            //     'Continuous flow instead of cards', mushafMode, onMushaf,
            //     isDark, false),
          ],
        ),
      ),
    );
  }

  Widget _prefTile(String title, String subtitle, bool value,
      Function(bool) onChanged, bool isDark, bool isFirst) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.grey.shade500)),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF1B4332),
      activeTrackColor: const Color(0xFF1B4332).withValues(alpha: 0.4),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16);
}

// ── Page 8: Finish ────────────────────────────────────────────────────────────
class _FinishPage extends StatelessWidget {
  final bool isDark;
  final String themeChoice;
  final String arabicFont;
  final String translationLang;
  final String wbwLang;
  final int dailyGoal;

  const _FinishPage({
    required this.isDark,
    required this.themeChoice,
    required this.arabicFont,
    required this.translationLang,
    required this.wbwLang,
    required this.dailyGoal,
  });

  String _label(String key, Map<String, String> map) =>
      map[key] ?? key;

  @override
  Widget build(BuildContext context) {
    final themeMap = {
      'light': '☀️ Light',
      'dark': '🌙 Dark',
      'system': '📱 System'
    };
    final fontMap = {
      'noorehuda': 'Noorehuda',
      'uthmani': 'Uthmani',
      'indopak': 'Indo-Pak'
    };
    final langMap = {'ur': '🇵🇰 Urdu', 'en': '🇬🇧 English', 'hi': '🇮🇳 Hindi'};
    final wbwMap = {
      'ur': '🇵🇰 Urdu',
      'en': '🇬🇧 English',
      'hi': '🇮🇳 Hindi',
      'off': '🚫 Off'
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
              ),
              border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                  width: 2),
            ),
            child: const Center(
                child: Text('🌟', style: TextStyle(fontSize: 40))),
          ),
          const SizedBox(height: 20),
          Text('You\'re all set!',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1B4332))),
          const SizedBox(height: 6),
          Text(
            'Your personalised Quran experience is ready.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2E1F) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                _summaryRow('Theme', _label(themeChoice, themeMap), isDark,
                    true),
                _divider(),
                _summaryRow(
                    'Arabic Font', _label(arabicFont, fontMap), isDark, false),
                _divider(),
                _summaryRow('Translation', _label(translationLang, langMap),
                    isDark, false),
                _divider(),
                _summaryRow(
                    'Word-by-Word', _label(wbwLang, wbwMap), isDark, false),
                _divider(),
                _summaryRow(
                    'Daily Goal', '$dailyGoal words/day', isDark, false),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B4332).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF1B4332).withValues(alpha: 0.2)),
            ),
            child: Text(
              'إِنَّ مَعَ الْعُسْرِ يُسْرًا\nبیشک مشکل کے ساتھ آسانی ہے',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF1B4332),
                height: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All settings can be changed from Profile & Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark, bool isFirst) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey.shade600)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16);
}