import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:metmusic/main.dart';

void main() {
  testWidgets('shows the search screen with an empty state', (tester) async {
    await tester.pumpWidget(const MetMusicApp());

    expect(find.text('YouTube Music'), findsOneWidget);
    expect(find.text('Search songs'), findsOneWidget);
    // The mini player is hidden until a track is selected.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });
}