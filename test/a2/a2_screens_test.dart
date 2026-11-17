import 'dart:io';

import 'package:fl_clash/views/a2_home.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('A2Sans', [
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    ]);
    await _loadFont('Twemoji', ['assets/fonts/Twemoji.Mozilla.ttf']);
    a2FontFamily = 'A2Sans';
  });

  for (final screen in ['login', 'off', 'on']) {
    testWidgets('A2 screen $screen', (tester) async {
      tester.view.physicalSize = const Size(840, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: a2Preview(screen: screen),
        ),
      );
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          final image = element.widget as Image;
          await precacheImage(image.image, element);
        }
      });
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(Directionality).first,
        matchesGoldenFile('goldens/a2_$screen.png'),
      );
    });
  }
}
