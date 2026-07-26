import 'package:sqflite/sqflite.dart';

class VocabRootImporter {
  final Database db;
  VocabRootImporter(this.db);

  Future<void> run() async {
    // For each vocab_word, find its stem segment and copy root_id and pos_id
    await db.execute('''
      UPDATE vocab_words
      SET
        root_id = (
          SELECT ms.root_id
          FROM morphology_segments ms
          JOIN ayah_words aw ON aw.id = ms.word_id
          WHERE aw.vocab_word_id = vocab_words.id
            AND ms.segment_type = 'stem'
            AND ms.root_id IS NOT NULL
          LIMIT 1
        ),
        pos_id = (
          SELECT ms.pos_id
          FROM morphology_segments ms
          JOIN ayah_words aw ON aw.id = ms.word_id
          WHERE aw.vocab_word_id = vocab_words.id
            AND ms.segment_type = 'stem'
            AND ms.pos_id IS NOT NULL
          LIMIT 1
        ),
        lemma = (
          SELECT ms.lemma
          FROM morphology_segments ms
          JOIN ayah_words aw ON aw.id = ms.word_id
          WHERE aw.vocab_word_id = vocab_words.id
            AND ms.segment_type = 'stem'
            AND ms.lemma != ''
          LIMIT 1
        )
      WHERE root_id IS NULL OR pos_id IS NULL
    ''');
  }
}