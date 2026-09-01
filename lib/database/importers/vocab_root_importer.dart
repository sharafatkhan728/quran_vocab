import 'package:sqflite/sqflite.dart';

/// VocabRootImporter — assigns root_id, pos_id, and lemma to vocab_words
/// using a majority-vote across morphology segments.
///
/// Optimized approach: builds indexed temp tables with ROW_NUMBER() to pick
/// the best root/pos/lemma per vocab word in a single set-based pass,
/// then UPDATEs vocab_words via JOIN instead of correlated subqueries.
class VocabRootImporter {
  final DatabaseExecutor db;
  VocabRootImporter(this.db);

  Future<void> run() async {
    // ── Step 1: Build indexed root frequency temp table ─────────────────────
    // ROW_NUMBER() picks the root_id with highest frequency per vocab_word,
    // ties broken by root_id DESC (deterministic, same as original).
    await db.execute('''
      CREATE TEMP TABLE _root_best (
        vocab_word_id INTEGER,
        root_id       INTEGER,
        rn            INTEGER
      )
    ''');
    await db.execute('''
      INSERT INTO _root_best (vocab_word_id, root_id, rn)
      SELECT vocab_word_id, root_id,
             ROW_NUMBER() OVER (
               PARTITION BY vocab_word_id
               ORDER BY freq DESC, root_id DESC
             ) AS rn
      FROM (
        SELECT
          aw.vocab_word_id,
          ms.root_id,
          COUNT(*) AS freq
        FROM morphology_segments ms
        JOIN ayah_words aw ON aw.id = ms.word_id
        WHERE ms.segment_type = 'stem'
          AND ms.root_id IS NOT NULL
          AND aw.vocab_word_id IS NOT NULL
        GROUP BY aw.vocab_word_id, ms.root_id
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS _idx_root_best ON _root_best(vocab_word_id)');

    // ── Step 2: Apply root_id via JOIN UPDATE ───────────────────────────────
    await db.execute('''
      UPDATE vocab_words
      SET root_id = (
        SELECT root_id FROM _root_best
        WHERE _root_best.vocab_word_id = vocab_words.id
          AND _root_best.rn = 1
      )
      WHERE EXISTS (
        SELECT 1 FROM _root_best
        WHERE _root_best.vocab_word_id = vocab_words.id
          AND _root_best.rn = 1
      )
    ''');

    // ── Step 3: Build indexed pos frequency temp table ──────────────────────
    await db.execute('''
      CREATE TEMP TABLE _pos_best (
        vocab_word_id INTEGER,
        pos_id        INTEGER,
        rn            INTEGER
      )
    ''');
    await db.execute('''
      INSERT INTO _pos_best (vocab_word_id, pos_id, rn)
      SELECT vocab_word_id, pos_id,
             ROW_NUMBER() OVER (
               PARTITION BY vocab_word_id
               ORDER BY freq DESC, pos_id DESC
             ) AS rn
      FROM (
        SELECT
          aw.vocab_word_id,
          ms.pos_id,
          COUNT(*) AS freq
        FROM morphology_segments ms
        JOIN ayah_words aw ON aw.id = ms.word_id
        WHERE ms.segment_type = 'stem'
          AND ms.pos_id IS NOT NULL
          AND aw.vocab_word_id IS NOT NULL
        GROUP BY aw.vocab_word_id, ms.pos_id
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS _idx_pos_best ON _pos_best(vocab_word_id)');

    // ── Step 4: Apply pos_id via JOIN UPDATE ────────────────────────────────
    await db.execute('''
      UPDATE vocab_words
      SET pos_id = (
        SELECT pos_id FROM _pos_best
        WHERE _pos_best.vocab_word_id = vocab_words.id
          AND _pos_best.rn = 1
      )
      WHERE EXISTS (
        SELECT 1 FROM _pos_best
        WHERE _pos_best.vocab_word_id = vocab_words.id
          AND _pos_best.rn = 1
      )
    ''');

    // ── Step 5: Build indexed lemma frequency temp table ────────────────────
    await db.execute('''
      CREATE TEMP TABLE _lemma_best (
        vocab_word_id INTEGER,
        lemma         TEXT,
        rn            INTEGER
      )
    ''');
    await db.execute('''
      INSERT INTO _lemma_best (vocab_word_id, lemma, rn)
      SELECT vocab_word_id, lemma,
             ROW_NUMBER() OVER (
               PARTITION BY vocab_word_id
               ORDER BY freq DESC, lemma DESC
             ) AS rn
      FROM (
        SELECT
          aw.vocab_word_id,
          ms.lemma,
          COUNT(*) AS freq
        FROM morphology_segments ms
        JOIN ayah_words aw ON aw.id = ms.word_id
        WHERE ms.segment_type = 'stem'
          AND ms.lemma != ''
          AND aw.vocab_word_id IS NOT NULL
        GROUP BY aw.vocab_word_id, ms.lemma
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS _idx_lemma_best ON _lemma_best(vocab_word_id)');

    // ── Step 6: Apply lemma via JOIN UPDATE ─────────────────────────────────
    await db.execute('''
      UPDATE vocab_words
      SET lemma = (
        SELECT lemma FROM _lemma_best
        WHERE _lemma_best.vocab_word_id = vocab_words.id
          AND _lemma_best.rn = 1
      )
      WHERE EXISTS (
        SELECT 1 FROM _lemma_best
        WHERE _lemma_best.vocab_word_id = vocab_words.id
          AND _lemma_best.rn = 1
      )
    ''');

    // ── Step 7: Clean up temp tables ────────────────────────────────────────
    await db.execute('DROP TABLE IF EXISTS _root_best');
    await db.execute('DROP TABLE IF EXISTS _pos_best');
    await db.execute('DROP TABLE IF EXISTS _lemma_best');
  }
}
