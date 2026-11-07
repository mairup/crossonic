/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:auto_route/auto_route.dart';
import 'package:crossonic/ui/main/main_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// simulates kIsWeb for rootTabStack in the test harness (kIsWeb is a const
// false under flutter_test)
var webMode = false;

void main() {
  setUp(() {
    webMode = false;
  });

  testWidgets(
    'switchTab resets to root when tab was initialized on a child route',
    (tester) async {
      final router = TestAppRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink([
              TestMainRoute(
                children: [
                  TestHomeTabRoute(
                    children: [TestArtistRoute(artistId: 'art-123')],
                  ),
                ],
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Artist: art-123'), findsOneWidget);
      expect(find.text('Home Screen'), findsNothing);

      // Tap Home navigation destination
      await tester.tap(find.byKey(const ValueKey('home_destination')));
      await tester.pumpAndSettle();

      // Now it should have replaced/reset to Home Screen!
      expect(find.text('Home Screen'), findsOneWidget);
      expect(find.text('Artist: art-123'), findsNothing);
    },
  );

  testWidgets('switchTab pops to root when tab has pushed child routes', (
    tester,
  ) async {
    final router = TestAppRouter();
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: (_) => const DeepLink([
            TestMainRoute(
              children: [
                TestHomeTabRoute(children: [TestHomeRoute()]),
              ],
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home Screen'), findsOneWidget);

    // Push artist route onto Home tab
    final tabsRouter = router.innerRouterOf<TabsRouter>(TestMainRoute.name)!;
    final homeStack = tabsRouter.stackRouterOfIndex(0)!;
    homeStack.push(TestArtistRoute(artistId: 'art-456'));
    await tester.pumpAndSettle();

    expect(find.text('Artist: art-456'), findsOneWidget);

    // Tap Home navigation destination
    await tester.tap(find.byKey(const ValueKey('home_destination')));
    await tester.pumpAndSettle();

    expect(find.text('Home Screen'), findsOneWidget);
    expect(find.text('Artist: art-456'), findsNothing);
  });

  testWidgets(
    'switchTab resets destination tab to root on web when switching to it',
    (tester) async {
      webMode = true;
      final router = TestAppRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router.config(
            deepLinkBuilder: (_) => const DeepLink([
              TestMainRoute(
                children: [
                  TestHomeTabRoute(children: [TestHomeRoute()]),
                ],
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabsRouter = router.innerRouterOf<TabsRouter>(TestMainRoute.name)!;
      final homeStack = tabsRouter.stackRouterOfIndex(0)!;
      homeStack.push(TestArtistRoute(artistId: 'art-789'));
      await tester.pumpAndSettle();
      expect(find.text('Artist: art-789'), findsOneWidget);

      // switch away to Browse and back to Home, simulating web (kIsWeb)
      await tester.tap(find.byKey(const ValueKey('browse_destination')));
      await tester.pumpAndSettle();
      expect(find.text('Browse Screen'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home_destination')));
      await tester.pumpAndSettle();

      expect(find.text('Home Screen'), findsOneWidget);
      expect(find.text('Artist: art-789'), findsNothing);
    },
  );

  testWidgets(
    'switchTab keeps destination tab stack on native when switching to it',
    (tester) async {
      final router = TestAppRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router.config(
            deepLinkBuilder: (_) => const DeepLink([
              TestMainRoute(
                children: [
                  TestHomeTabRoute(children: [TestHomeRoute()]),
                ],
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabsRouter = router.innerRouterOf<TabsRouter>(TestMainRoute.name)!;
      final homeStack = tabsRouter.stackRouterOfIndex(0)!;
      homeStack.push(TestArtistRoute(artistId: 'art-789'));
      await tester.pumpAndSettle();
      expect(find.text('Artist: art-789'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('browse_destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home_destination')));
      await tester.pumpAndSettle();

      // native keeps the deep stack: the artist page is still on top
      expect(find.text('Artist: art-789'), findsOneWidget);
    },
  );
}

// Minimal reproduction routes and router matching Crossonic structure
class TestAppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      path: '/',
      page: TestMainRoute.page,
      initial: true,
      children: [
        AutoRoute(
          path: 'home',
          page: TestHomeTabRoute.page,
          children: [
            AutoRoute(page: TestHomeRoute.page, path: ''),
            AutoRoute(page: TestArtistRoute.page, path: 'artist/:id'),
          ],
        ),
        AutoRoute(
          path: 'browse',
          page: TestBrowseTabRoute.page,
          children: [
            AutoRoute(page: TestBrowseRoute.page, path: ''),
            AutoRoute(page: TestArtistRoute.page, path: 'artist/:id'),
          ],
        ),
      ],
    ),
  ];
}

class TestMainRoute extends PageRouteInfo<void> {
  const TestMainRoute({List<PageRouteInfo>? children})
    : super(TestMainRoute.name, initialChildren: children);
  static const String name = 'TestMainRoute';
  static PageInfo page = PageInfo(
    name,
    builder: (data) => const TestMainPage(),
  );
}

class TestHomeTabRoute extends PageRouteInfo<void> {
  const TestHomeTabRoute({List<PageRouteInfo>? children})
    : super(TestHomeTabRoute.name, initialChildren: children);
  static const String name = 'TestHomeTabRoute';
  static PageInfo page = PageInfo(name, builder: (data) => const AutoRouter());
}

class TestBrowseTabRoute extends PageRouteInfo<void> {
  const TestBrowseTabRoute({List<PageRouteInfo>? children})
    : super(TestBrowseTabRoute.name, initialChildren: children);
  static const String name = 'TestBrowseTabRoute';
  static PageInfo page = PageInfo(name, builder: (data) => const AutoRouter());
}

class TestHomeRoute extends PageRouteInfo<void> {
  const TestHomeRoute() : super(TestHomeRoute.name);
  static const String name = 'TestHomeRoute';
  static PageInfo page = PageInfo(
    name,
    builder: (data) => const Scaffold(body: Center(child: Text('Home Screen'))),
  );
}

class TestBrowseRoute extends PageRouteInfo<void> {
  const TestBrowseRoute() : super(TestBrowseRoute.name);
  static const String name = 'TestBrowseRoute';
  static PageInfo page = PageInfo(
    name,
    builder: (data) =>
        const Scaffold(body: Center(child: Text('Browse Screen'))),
  );
}

class TestArtistRoute extends PageRouteInfo<TestArtistRouteArgs> {
  TestArtistRoute({required String artistId})
    : super(
        TestArtistRoute.name,
        args: TestArtistRouteArgs(artistId: artistId),
        rawPathParams: {'id': artistId},
      );
  static const String name = 'TestArtistRoute';
  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TestArtistRouteArgs>(
        orElse: () => TestArtistRouteArgs(
          artistId: data.params.getString('id', 'unknown'),
        ),
      );
      return Scaffold(body: Center(child: Text('Artist: ${args.artistId}')));
    },
  );
}

class TestArtistRouteArgs {
  final String artistId;
  TestArtistRouteArgs({required this.artistId});
}

class TestMainPage extends StatelessWidget {
  const TestMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      routes: const [TestHomeRoute(), TestBrowseRoute()],
      homeIndex: 0,
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);

        Future<void> switchTab(int index) async {
          final (targetRoute, targetRouteName) = switch (index) {
            0 => (const TestHomeRoute(), TestHomeRoute.name),
            1 => (const TestBrowseRoute(), TestBrowseRoute.name),
            _ => (null, ''),
          };

          final router = tabsRouter.stackRouterOfIndex(index);

          if (index == tabsRouter.activeIndex) {
            if (router != null) {
              rootTabStack(
                router,
                targetRoute: targetRoute,
                targetRouteName: targetRouteName,
                resetToRoot: true,
              );
            }
            return;
          }

          tabsRouter.setActiveIndex(index);

          final destRouter = tabsRouter.stackRouterOfIndex(index);
          if (destRouter != null) {
            rootTabStack(
              destRouter,
              targetRoute: targetRoute,
              targetRouteName: targetRouteName,
              resetToRoot: webMode,
            );
          }
        }

        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: tabsRouter.activeIndex,
                onDestinationSelected: switchTab,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home, key: ValueKey('home_destination')),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(
                      Icons.library_music,
                      key: ValueKey('browse_destination'),
                    ),
                    label: Text('Browse'),
                  ),
                ],
              ),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}
