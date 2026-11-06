/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:crossonic/data/repositories/audio/queue/queue_manager.dart';
import 'package:crossonic/data/repositories/keyvalue/key_value_repository.dart';
import 'package:crossonic/data/repositories/song/song_repository.dart';
import 'package:crossonic/data/repositories/subsonic/favorites_repository.dart';
import 'package:crossonic/data/repositories/subsonic/models/song.dart';
import 'package:crossonic/data/services/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFavoritesRepository extends Mock implements FavoritesRepository {}

Song makeSong(String id) => Song(
      id: id,
      coverId: 'cover-$id',
      title: 'Song $id',
      displayArtist: 'Artist',
      artists: const [],
      album: null,
      genres: const [],
      duration: null,
      bpm: null,
      trackNr: null,
      discNr: null,
      trackGain: null,
      albumGain: null,
      fallbackGain: null,
      originalDate: null,
      releaseDate: null,
      contentType: null,
      sampleRate: null,
      bitDepth: null,
      bitRate: null,
    );

void main() {
  late Database db;
  late QueueManager queue;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    final songRepository = SongRepository(
      db: db,
      favorites: MockFavoritesRepository(),
    );
    final keyValueRepository = KeyValueRepository(database: db);
    queue = QueueManager(
      db: db,
      songRepo: songRepository,
      keyValue: keyValueRepository,
    );
    await queue.init();
  });

  tearDown(() async {
    await db.close();
  });

  test("out of bounds insertAll into priority queue reports priority queue length", () async {
    final songs = [makeSong("s1"), makeSong("s2"), makeSong("s3")];
    for (final song in songs) {
      await db.managers.songTable.create(
        (o) => o(
          id: song.id,
          coverId: song.coverId,
          title: song.title,
          displayArtist: song.displayArtist,
          updated: DateTime.now(),
        ),
      );
    }
    await queue.addAll([songs[0], songs[1]], false);
    expect(queue.length, 2);
    expect(queue.priorityLength, 0);

    Object? error;
    try {
      await queue.insertAll(1, [songs[2]], true);
    } catch (e) {
      error = e;
    }
    expect(error, isA<IndexError>());
    // the error must describe the priority queue, not the regular queue
    expect((error as IndexError).length, 0);
  });
}
