/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:auto_route/auto_route.dart';
import 'package:crossonic/data/repositories/auth/auth_repository.dart';
import 'package:crossonic/routing/auth_guard.dart';
import 'package:crossonic/routing/main_toplevel_guard.dart';
import 'package:crossonic/routing/router.gr.dart';
import 'package:crossonic/system_integration.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  final AuthRepository _authRepository;

  AppRouter({required this._authRepository});

  @override
  // TODO: implement defaultRouteType
  RouteType get defaultRouteType => const RouteType.material(
    // disables custom predictive back transition and uses configured default value
    enablePredictiveBackGesture: false,
  );

  @override
  List<AutoRouteGuard> get guards => [
    AuthGuard(authRepository: _authRepository),
  ];

  final List<AutoRoute> _childRoutes = [
    AutoRoute(
      path: "release/:id",
      page: AlbumRoute.page,
      title: (context, data) => "Release",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "artist/:id",
      page: ArtistRoute.page,
      title: (context, data) => "Artist",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "playlist/:id",
      page: PlaylistRoute.page,
      title: (context, data) => "Playlist",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "playlist/create",
      page: CreatePlaylistRoute.page,
      title: (context, data) => "Create Playlist",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "playlist/update/:id",
      page: UpdatePlaylistRoute.page,
      title: (context, data) => "Update Playlist",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "artists",
      page: ArtistsRoute.page,
      title: (context, data) => "Artists",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "releases",
      page: AlbumsRoute.page,
      title: (context, data) => "Releases",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "songs",
      page: SongsRoute.page,
      title: (context, data) => "Songs",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "genres",
      page: GenresRoute.page,
      title: (context, data) => "Genres",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "years",
      page: YearsRoute.page,
      title: (context, data) => "Years",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "bpm",
      page: BpmRoute.page,
      title: (context, data) => "BPM",
      restorationId: (match) => match.fullPath,
    ),
  ];

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      initial: true,
      path: "/",
      page: MainRoute.page,
      guards: [const MainTopLevelGuard()],
      children: [
        AutoRoute(
          path: "home",
          page: const EmptyShellRoute("HomeTab"),
          title: (context, data) => "",
          children: [
            AutoRoute(
              page: HomeRoute.page,
              path: "",
              title: (context, data) => "Home",
            ),
            ..._childRoutes,
          ],
          restorationId: (match) => match.fullPath,
        ),
        AutoRoute(
          path: "browse",
          page: const EmptyShellRoute("BrowseTab"),
          title: (context, data) => "",
          children: [
            AutoRoute(
              page: BrowseRoute.page,
              path: "",
              title: (context, data) => "Browse",
            ),
            ..._childRoutes,
          ],
          restorationId: (match) => match.fullPath,
        ),
        AutoRoute(
          path: "playlists",
          page: const EmptyShellRoute("PlaylistTab"),
          title: (context, data) => "",
          children: [
            AutoRoute(
              page: PlaylistsRoute.page,
              path: "",
              title: (context, data) => "Playlists",
            ),
            ..._childRoutes,
          ],
          restorationId: (match) => match.fullPath,
        ),
      ],
    ),
    AutoRoute(
      path: "/auth/connect",
      page: ConnectServerRoute.page,
      title: (context, data) => "Connect Server",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/auth/login",
      page: LoginRoute.page,
      title: (context, data) => "Login",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/queue",
      page: QueueRoute.page,
      title: (context, data) => "Queue",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/queue/select",
      page: SelectQueueRoute.page,
      title: (context, data) => "Select Queue",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings",
      page: SettingsRoute.page,
      title: (context, data) => "Settings",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/musicFolders",
      page: MusicFoldersRoute.page,
      title: (context, data) => "Music Folders",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/homeLayout",
      page: HomeLayoutRoute.page,
      title: (context, data) => "Home Layout",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/appearance",
      page: AppearanceRoute.page,
      title: (context, data) => "Appearance",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/transcoding",
      page: TranscodingRoute.page,
      title: (context, data) => "Transcoding",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/replayGain",
      page: ReplayGainRoute.page,
      title: (context, data) => "Replay Gain",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/prefetch",
      page: PrefetchRoute.page,
      title: (context, data) => "Queue Prefetching",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/scan",
      page: ScanRoute.page,
      title: (context, data) => "Scan",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/listenBrainz",
      page: ListenBrainzRoute.page,
      title: (context, data) => "ListenBrainz",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/debug",
      page: DebugRoute.page,
      title: (context, data) => "Debug",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/debug/logs",
      page: LogsRoute.page,
      title: (context, data) => "Logs",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/debug/logs/chooseSession",
      page: ChooseLogSessionRoute.page,
      title: (context, data) => "Choose Session",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/settings/debug/logs/details",
      page: LogDetailsRoute.page,
      title: (context, data) => "Message Details",
      restorationId: (match) => match.fullPath,
    ),
    if (!systemIntegrationConfig.versionCheckExternallyDisabled) ...[
      AutoRoute(
        path: "/settings/updates",
        page: UpdatesRoute.page,
        title: (context, data) => "Updates",
        restorationId: (match) => match.fullPath,
      ),
    ],
    AutoRoute(
      path: "/lyrics",
      page: LyricsRoute.page,
      title: (context, data) => "Lyrics",
      restorationId: (match) => match.fullPath,
    ),
    AutoRoute(
      path: "/cast",
      page: CastingRoute.page,
      title: (context, data) => "Casting",
      restorationId: (match) => match.fullPath,
    ),
  ];
}

/// Tab shell route name -> name of the route that roots the shell's stack.
const Map<String, String> _tabRootRouteNames = {
  "HomeTab": HomeRoute.name,
  "BrowseTab": BrowseRoute.name,
  "PlaylistTab": PlaylistsRoute.name,
};

/// Deep link builder that roots every tab shell at its root route.
///
/// On web the URL is the source of truth on cold start and on every browser
/// history event (popstate), and a deep URL like /home/artist/:id would
/// otherwise rebuild the home tab stack with the artist page as its first
/// entry, so the home button would no longer know where the tab root is.
DeepLink tabRootDeepLinkBuilder(PlatformDeepLink link) =>
    DeepLink(rootedTabRoutes(link.matches));

/// Returns [matches] as route infos with tab shells rooted at their root
/// route (e.g. HomeTab[HomeRoute, ArtistRoute] instead of HomeTab[ArtistRoute]).
List<PageRouteInfo> rootedTabRoutes(List<RouteMatch> matches) {
  return matches.map(_rootedTabMatch).toList();
}

PageRouteInfo _rootedTabMatch(RouteMatch match) {
  final rootName = _tabRootRouteNames[match.name];
  var children = match.children?.map(_rootedTabMatch).toList();
  if (rootName != null &&
      children != null &&
      children.isNotEmpty &&
      children.first.routeName != rootName) {
    children = [PageRouteInfo(rootName), ...children];
  }
  return PageRouteInfo(
    match.name,
    rawPathParams: match.params.rawMap,
    rawQueryParams: match.queryParams.rawMap,
    fragment: match.fragment,
    redirectedFrom: match.redirectedFrom,
    stringMatch: match.stringMatch,
    args: match.args,
    initialChildren: children,
  );
}
