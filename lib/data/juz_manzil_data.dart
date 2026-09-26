/// Har Juz aur Manzil ka starting point (Surah, Ayah) — Quran ki fixed
/// taqseem hai isliye hardcoded hai (koi database call nahi lagti).
class JuzManzilData {
  static const Map<int, (int, int)> juzStarts = {
    1: (1, 1), 2: (2, 142), 3: (2, 253), 4: (3, 93), 5: (4, 24),
    6: (4, 148), 7: (5, 82), 8: (6, 111), 9: (7, 88), 10: (8, 41),
    11: (9, 93), 12: (11, 6), 13: (12, 53), 14: (15, 1), 15: (17, 1),
    16: (18, 75), 17: (21, 1), 18: (23, 1), 19: (25, 21), 20: (27, 56),
    21: (29, 46), 22: (33, 31), 23: (36, 28), 24: (39, 32), 25: (41, 47),
    26: (46, 1), 27: (51, 31), 28: (58, 1), 29: (67, 1), 30: (78, 1),
  };

  static const Map<int, (int, int)> manzilStarts = {
    1: (1, 1), 2: (5, 1), 3: (10, 1), 4: (17, 1),
    5: (26, 1), 6: (37, 1), 7: (50, 1),
  };

  static (int, int) juzSurahRange(int juz) {
    final start = juzStarts[juz]!.$1;
    final next = juzStarts[juz + 1];
    final end = next == null ? 114 : (next.$2 == 1 ? next.$1 - 1 : next.$1);
    return (start, end < start ? start : end);
  }

  static (int, int) manzilSurahRange(int manzil) {
    final start = manzilStarts[manzil]!.$1;
    final next = manzilStarts[manzil + 1];
    final end = next == null ? 114 : (next.$2 == 1 ? next.$1 - 1 : next.$1);
    return (start, end < start ? start : end);
  }
}