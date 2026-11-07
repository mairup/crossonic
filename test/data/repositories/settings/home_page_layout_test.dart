/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:crossonic/data/repositories/keyvalue/key_value_repository.dart';
import 'package:crossonic/data/repositories/settings/home_page_layout.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKeyValue extends Fake implements KeyValueRepository {
  List<String>? stored;

  @override
  Future<List<String>?> loadStringList(String key) async => stored;

  @override
  Future<void> store<T>(String key, T value) async {}

  @override
  Future<void> remove(String key) async {}
}

void main() {
  late _FakeKeyValue keyValue;

  setUp(() {
    keyValue = _FakeKeyValue(); // fresh install: nothing stored
  });

  test('fork default home layout matches the agreed layout', () async {
    final settings = HomeLayoutSettings(keyValueRepository: keyValue);
    await settings.load();
    expect(settings.selectedOptions, [
      HomeContentOption.recentlyAddedReleases,
      HomeContentOption.recentlyPlayedReleases,
      HomeContentOption.frequentlyPlayedReleases,
      HomeContentOption.favoriteSongs,
      HomeContentOption.randomSongs,
      HomeContentOption.favoriteReleases,
      HomeContentOption.randomReleases,
    ]);
    settings.dispose();
  });

  test('a stored custom layout is kept, not overwritten by the default', () async {
    keyValue.stored = [HomeContentOption.randomArtists.name];
    final settings = HomeLayoutSettings(keyValueRepository: keyValue);
    await settings.load();
    expect(settings.selectedOptions, [HomeContentOption.randomArtists]);
    settings.dispose();
  });

  test('reset restores the fork default', () async {
    final settings = HomeLayoutSettings(keyValueRepository: keyValue);
    await settings.load();
    settings.selectedOptions = [HomeContentOption.favoriteArtists];
    settings.reset();
    expect(settings.selectedOptions.length, 7);
    expect(
      settings.selectedOptions.first,
      HomeContentOption.recentlyAddedReleases,
    );
    settings.dispose();
  });
}
