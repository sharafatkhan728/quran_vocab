import 'package:sqflite/sqflite.dart';

class VocabRootImporter {
  final DatabaseExecutor db;
  VocabRootImporter(this.db);

  Future<void> run() async {
    // ── Fix: use majority-vote root instead of LIMIT 1 (arbitrary) ──────────
    //
    // A vocab_word can appear in many ayahs. Each occurrence has morphology
    // segments. The same normalized arabic_clean can theoretically have
    // different roots across occurrences (rare but real — e.g. homographs).
    // LIMIT 1 with no ORDER BY returns an arbitrary row.
    //
    // Fix: pick the root_id that appears MOST FREQUENTLY across all
    // morphology segments for that vocab word. This is the statistically
    // correct root for that word form.

    // Step 1: build a frequency table of (vocab_word_id, root_id) pairs
    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS _root_freq AS
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
    ''');

    // Step 2: for each vocab_word, pick the root_id with highest frequency
    // (ties broken by root_id DESC — deterministic)
    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS _best_root AS
      SELECT vocab_word_id, root_id
      FROM _root_freq r1
      WHERE freq = (
        SELECT MAX(freq) FROM _root_freq r2
        WHERE r2.vocab_word_id = r1.vocab_word_id
      )
      GROUP BY vocab_word_id
      HAVING MAX(root_id)
    ''');

    // Step 3: apply best root to vocab_words
    await db.execute('''
      UPDATE vocab_words
      SET root_id = (
        SELECT root_id FROM _best_root
        WHERE _best_root.vocab_word_id = vocab_words.id
      )
      WHERE EXISTS (
        SELECT 1 FROM _best_root
        WHERE _best_root.vocab_word_id = vocab_words.id
      )
    ''');

    // Step 4: build frequency table for pos_id similarly
    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS _pos_freq AS
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
    ''');

    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS _best_pos AS
      SELECT vocab_word_id, pos_id
      FROM _pos_freq p1
      WHERE freq = (
        SELECT MAX(freq) FROM _pos_freq p2
        WHERE p2.vocab_word_id = p1.vocab_word_id
      )
      GROUP BY vocab_word_id
      HAVING MAX(pos_id)
    ''');

    await db.execute('''
      UPDATE vocab_words
      SET pos_id = (
        SELECT pos_id FROM _best_pos
        WHERE _best_pos.vocab_word_id = vocab_words.id
      )
      WHERE EXISTS (
        SELECT 1 FROM _best_pos
        WHERE _best_pos.vocab_word_id = vocab_words.id
      )
    ''');

    // Step 5: lemma — pick most frequent non-empty lemma for each vocab word
    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS _lemma_freq AS
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
    ''');

    await db.execute('''
      CREATE TEMP TABLE IF NOT EXISTS _best_lemma AS
      SELECT vocab_word_id, lemma
      FROM _lemma_freq l1
      WHERE freq = (
        SELECT MAX(freq) FROM _lemma_freq l2
        WHERE l2.vocab_word_id = l1.vocab_word_id
      )
      GROUP BY vocab_word_id
      HAVING MAX(lemma)
    ''');

    await db.execute('''
      UPDATE vocab_words
      SET lemma = (
        SELECT lemma FROM _best_lemma
        WHERE _best_lemma.vocab_word_id = vocab_words.id
      )
      WHERE EXISTS (
        SELECT 1 FROM _best_lemma
        WHERE _best_lemma.vocab_word_id = vocab_words.id
      )
    ''');

    // Step 6: clean up temp tables
    await db.execute('DROP TABLE IF EXISTS _root_freq');
    await db.execute('DROP TABLE IF EXISTS _best_root');
    await db.execute('DROP TABLE IF EXISTS _pos_freq');
    await db.execute('DROP TABLE IF EXISTS _best_pos');
    await db.execute('DROP TABLE IF EXISTS _lemma_freq');
    await db.execute('DROP TABLE IF EXISTS _best_lemma');
  }
}











//niche wala kaam krra agar upar wala na kre to 
// import 'package:sqflite/sqflite.dart';

// class VocabRootImporter {
//   final DatabaseExecutor db;
//   VocabRootImporter(this.db);

//   Future<void> run() async {
//     // For each vocab_word, find its stem segment and copy root_id and pos_id
//     await db.execute('''
//       UPDATE vocab_words
//       SET
//         root_id = (
//           SELECT ms.root_id
//           FROM morphology_segments ms
//           JOIN ayah_words aw ON aw.id = ms.word_id
//           WHERE aw.vocab_word_id = vocab_words.id
//             AND ms.segment_type = 'stem'
//             AND ms.root_id IS NOT NULL
//           LIMIT 1
//         ),
//         pos_id = (
//           SELECT ms.pos_id
//           FROM morphology_segments ms
//           JOIN ayah_words aw ON aw.id = ms.word_id
//           WHERE aw.vocab_word_id = vocab_words.id
//             AND ms.segment_type = 'stem'
//             AND ms.pos_id IS NOT NULL
//           LIMIT 1
//         ),
//         lemma = (
//           SELECT ms.lemma
//           FROM morphology_segments ms
//           JOIN ayah_words aw ON aw.id = ms.word_id
//           WHERE aw.vocab_word_id = vocab_words.id
//             AND ms.segment_type = 'stem'
//             AND ms.lemma != ''
//           LIMIT 1
//         )
//       WHERE root_id IS NULL OR pos_id IS NULL
//     ''');
//   }
// }
