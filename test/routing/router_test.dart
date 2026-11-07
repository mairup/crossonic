/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:auto_route/auto_route.dart';
import 'package:crossonic/data/repositories/auth/auth_repository.dart';
import 'package:crossonic/routing/router.dart';
import 'package:crossonic/routing/router.gr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

PageRouteInfo? _findByName(PageRouteInfo route, String name) {
  if (route.routeName == name) return route;
  for (final child in route.initialChildren ?? const []) {
    final found = _findByName(child, name);
    if (found != null) return found;
  }
  return null;
}

void main() {
  late AppRouter router;

  setUp(() {
    router = AppRouter(authRepository: MockAuthRepository());
  });

  test('rootedTabRoutes roots a tab shell matched from a deep URL', () {
    final matches = router.matcher.match('/home/artist/abc')!;
    final routes = rootedTabRoutes(matches);

    final homeTab = routes.map((r) => _findByName(r, 'HomeTab')).nonNulls.single;
    expect(homeTab.initialChildren!.first.routeName, HomeRoute.name);
    expect(homeTab.initialChildren!.last.routeName, ArtistRoute.name);
    expect(
      homeTab.initialChildren!.last.rawPathParams,
      containsPair('id', 'abc'),
    );
  });

  test('rootedTabRoutes leaves an already rooted tab untouched', () {
    final matches = router.matcher.match('/home')!;
    final routes = rootedTabRoutes(matches);

    final homeTab = routes.map((r) => _findByName(r, 'HomeTab')).nonNulls.single;
    expect(
      homeTab.initialChildren!.map((c) => c.routeName),
      [HomeRoute.name],
    );
  });

  test('rootedTabRoutes roots every tab shell independently', () {
    final matches = router.matcher.match('/playlists/playlist/p-1')!;
    final routes = rootedTabRoutes(matches);

    final playlistTab = routes
        .map((r) => _findByName(r, 'PlaylistTab'))
        .nonNulls
        .single;
    expect(playlistTab.initialChildren!.first.routeName, PlaylistsRoute.name);
    expect(playlistTab.initialChildren!.last.routeName, PlaylistRoute.name);
  });

  test('rootedTabRoutes leaves non-tab routes untouched', () {
    final matches = router.matcher.match('/settings')!;
    final routes = rootedTabRoutes(matches);

    expect(routes.single.routeName, SettingsRoute.name);
    expect(routes.single.hasChildren, isFalse);
  });
}
