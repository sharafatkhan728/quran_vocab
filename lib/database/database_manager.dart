import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseManager {
  static Database? _db;
  static const int _schemaVersion = 2;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = join(await getDatabasesPath(), 'quran.db');
    return openDatabase(
      dbPath,
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    final statements = _sql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (final stmt in statements) {
      await db.execute('$stmt;');
    }
  }

  static Future<void> _onUpgrade(Database db, int old, int newV) async {
    if (old < 2) {
      // Check if column already exists before adding
      final cols = await db.rawQuery('PRAGMA table_info(srs_cards)');
      final exists = cols.any((c) => c['name'] == 'is_deleted');
      if (!exists) {
        await db.execute(
            'ALTER TABLE srs_cards ADD COLUMN is_deleted INTEGER DEFAULT 0');
      }
    }
  }

  static const String _sql = '''
    CREATE TABLE IF NOT EXISTS roots (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      arabic     TEXT NOT NULL UNIQUE,
      meaning_ur TEXT DEFAULT '',
      meaning_en TEXT DEFAULT ''
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_roots_arabic ON roots(arabic)
    ;
    CREATE TABLE IF NOT EXISTS parts_of_speech (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      code        TEXT NOT NULL UNIQUE,
      name_en     TEXT NOT NULL,
      name_ur     TEXT DEFAULT '',
      color_hex   TEXT DEFAULT '#888888',
      description TEXT DEFAULT ''
    )
    ;
    CREATE TABLE IF NOT EXISTS surahs (
      id              INTEGER PRIMARY KEY,
      name_arabic     TEXT NOT NULL,
      name_english    TEXT NOT NULL,
      name_urdu       TEXT NOT NULL,
      revelation_type TEXT NOT NULL,
      verse_count     INTEGER NOT NULL,
      juz_start       INTEGER NOT NULL,
      page_start      INTEGER DEFAULT 0
    )
    ;
    CREATE TABLE IF NOT EXISTS ayahs (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      surah_id     INTEGER NOT NULL REFERENCES surahs(id),
      ayah_number  INTEGER NOT NULL,
      arabic_text  TEXT NOT NULL,
      juz_number   INTEGER NOT NULL,
      page_number  INTEGER DEFAULT 0,
      ruku_number  INTEGER DEFAULT 0,
      is_bismillah INTEGER DEFAULT 0,
      sajda_type   TEXT DEFAULT '',
      UNIQUE(surah_id, ayah_number)
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_ayahs_surah ON ayahs(surah_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_ayahs_juz ON ayahs(juz_number)
    ;
    CREATE TABLE IF NOT EXISTS ayah_translations (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      ayah_id     INTEGER NOT NULL REFERENCES ayahs(id),
      language    TEXT NOT NULL,
      scholar_key TEXT NOT NULL,
      text        TEXT NOT NULL,
      UNIQUE(ayah_id, language, scholar_key)
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_aytrans_ayah ON ayah_translations(ayah_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_aytrans_lang ON ayah_translations(language, scholar_key)
    ;
    CREATE TABLE IF NOT EXISTS vocab_words (
      id                  INTEGER PRIMARY KEY AUTOINCREMENT,
      arabic_clean        TEXT NOT NULL UNIQUE,
      arabic_display      TEXT NOT NULL,
      root_id             INTEGER REFERENCES roots(id),
      lemma               TEXT DEFAULT '',
      pos_id              INTEGER REFERENCES parts_of_speech(id),
      frequency           INTEGER DEFAULT 0,
      first_surah_id      INTEGER REFERENCES surahs(id),
      first_ayah_number   INTEGER DEFAULT 0,
      first_word_position INTEGER DEFAULT 0,
      meaning_ur          TEXT DEFAULT '',
      meaning_en          TEXT DEFAULT '',
      meaning_hi          TEXT DEFAULT '',
      meaning_en_raw      TEXT DEFAULT ''
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_vocab_clean     ON vocab_words(arabic_clean)
    ;
    CREATE INDEX IF NOT EXISTS idx_vocab_root      ON vocab_words(root_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_vocab_pos       ON vocab_words(pos_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_vocab_frequency ON vocab_words(frequency DESC)
    ;
    CREATE INDEX IF NOT EXISTS idx_vocab_lemma     ON vocab_words(lemma)
    ;
    CREATE TABLE IF NOT EXISTS ayah_words (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      ayah_id       INTEGER NOT NULL REFERENCES ayahs(id),
      position      INTEGER NOT NULL,
      arabic_text   TEXT NOT NULL,
      arabic_clean  TEXT NOT NULL,
      is_waqf       INTEGER DEFAULT 0,
      vocab_word_id INTEGER REFERENCES vocab_words(id),
      UNIQUE(ayah_id, position)
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_ayahwords_ayah  ON ayah_words(ayah_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_ayahwords_vocab ON ayah_words(vocab_word_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_ayahwords_clean ON ayah_words(arabic_clean)
    ;
    CREATE TABLE IF NOT EXISTS word_translations (
      id       INTEGER PRIMARY KEY AUTOINCREMENT,
      word_id  INTEGER NOT NULL REFERENCES ayah_words(id),
      language TEXT NOT NULL,
      text     TEXT NOT NULL,
      text_raw TEXT DEFAULT '',
      UNIQUE(word_id, language)
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_wordtrans_word ON word_translations(word_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_wordtrans_lang ON word_translations(language)
    ;
    CREATE TABLE IF NOT EXISTS morphology_segments (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      word_id          INTEGER NOT NULL REFERENCES ayah_words(id),
      segment_number   INTEGER NOT NULL,
      segment_type     TEXT NOT NULL,
      arabic_text      TEXT NOT NULL,
      pos_id           INTEGER REFERENCES parts_of_speech(id),
      root_id          INTEGER REFERENCES roots(id),
      lemma            TEXT DEFAULT '',
      tense            TEXT DEFAULT '',
      person           TEXT DEFAULT '',
      gender           TEXT DEFAULT '',
      number           TEXT DEFAULT '',
      grammatical_case TEXT DEFAULT '',
      voice            TEXT DEFAULT '',
      state            TEXT DEFAULT '',
      verb_form        TEXT DEFAULT '',
      raw_tag          TEXT NOT NULL,
      UNIQUE(word_id, segment_number)
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_morph_word  ON morphology_segments(word_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_morph_root  ON morphology_segments(root_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_morph_lemma ON morphology_segments(lemma)
    ;
    CREATE INDEX IF NOT EXISTS idx_morph_pos   ON morphology_segments(pos_id)
    ;
    CREATE TABLE IF NOT EXISTS db_meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ;
    CREATE TABLE IF NOT EXISTS known_words (
      vocab_word_id INTEGER PRIMARY KEY REFERENCES vocab_words(id),
      marked_at     INTEGER NOT NULL
    )
    ;
    CREATE TABLE IF NOT EXISTS srs_cards (
      vocab_word_id       INTEGER PRIMARY KEY REFERENCES vocab_words(id),
      stage               INTEGER DEFAULT 0,
      next_review_session INTEGER DEFAULT 0,
      ease_factor         REAL DEFAULT 2.5,
      fail_count          INTEGER DEFAULT 0,
      total_reviews       INTEGER DEFAULT 0,
      last_result         INTEGER DEFAULT -1,
      is_deleted          INTEGER DEFAULT 0,
      created_at          INTEGER NOT NULL,
      updated_at          INTEGER NOT NULL
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_srs_session ON srs_cards(next_review_session)
    ;
    CREATE INDEX IF NOT EXISTS idx_srs_stage ON srs_cards(stage)
    ;
    CREATE TABLE IF NOT EXISTS reading_progress (
      surah_id     INTEGER PRIMARY KEY REFERENCES surahs(id),
      last_ayah    INTEGER DEFAULT 0,
      last_read_at INTEGER NOT NULL
    )
    ;
    CREATE TABLE IF NOT EXISTS bookmarks (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      surah_id    INTEGER NOT NULL REFERENCES surahs(id),
      ayah_number INTEGER NOT NULL,
      created_at  INTEGER NOT NULL,
      note        TEXT DEFAULT '',
      UNIQUE(surah_id, ayah_number)
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_bookmarks_surah ON bookmarks(surah_id)
    ;
    CREATE TABLE IF NOT EXISTS daily_stats (
      date_key      TEXT PRIMARY KEY,
      words_learned INTEGER DEFAULT 0,
      sessions      INTEGER DEFAULT 0,
      points        INTEGER DEFAULT 0
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_daily_date ON daily_stats(date_key DESC)
    ;
    CREATE TABLE IF NOT EXISTS user_notes (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      surah_id      INTEGER REFERENCES surahs(id),
      ayah_number   INTEGER,
      vocab_word_id INTEGER REFERENCES vocab_words(id),
      note_text     TEXT NOT NULL,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL
    )
    ;
    CREATE INDEX IF NOT EXISTS idx_notes_surah ON user_notes(surah_id)
    ;
    CREATE INDEX IF NOT EXISTS idx_notes_vocab ON user_notes(vocab_word_id)
    ;
    CREATE TABLE IF NOT EXISTS user_meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''';

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}