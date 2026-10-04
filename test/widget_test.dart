import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metmusic/app/app_services.dart';
import 'package:metmusic/app/music_controller.dart';
import 'package:metmusic/main.dart';

void main() {
  testWidgets('shows the search screen with an empty state', (tester) async {
    // The desktop test host has no WebView, so the challenge solvers are
    // omitted and no network is touched while the tree is built.
    final services = AppServices.create();

    // The controller owns the services and disposes them when the widget tree
    // is torn down, so no separate teardown is registered here.
    await tester.pumpWidget(MetMusicApp(controller: MusicController(services)));

    expect(find.text('YouTube Music'), findsOneWidget);
    expect(find.text('Search songs'), findsOneWidget);
    // The player bar is hidden until a track is selected.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });
}