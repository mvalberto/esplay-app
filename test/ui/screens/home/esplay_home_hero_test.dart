import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/screens/home/esplay_home_hero.dart';

// The showcase at the top of a TV's Home lays out on a 1080p TV canvas, with
// its picture or, once it plays, a video under the same fade. With SHOTS set
// it also writes what it drew there, for a look.
void main() {
  const item = AggregatedItem(
    id: '1',
    serverId: 's',
    rawData: {
      'Name': 'El encuentro con un título largo que ocupa dos líneas enteras',
      'Type': 'Movie',
      'ProductionYear': 2021,
      'OfficialRating': 'ES-16',
      'CommunityRating': 5.9,
      'RunTimeTicks': 64800000000,
      'Genres': ['Misterio', 'Suspense', 'Drama'],
      'Overview':
          'Riz Ahmed interpreta a Malik Khan, un exmarine que, después de varios '
          'viajes a zonas de guerra, vuelve a casa y se entera de un siniestro '
          'secreto: una especie alienígena se está apoderando de las personas.',
    },
  );

  for (final playing in [false, true]) {
    testWidgets('lays out ${playing ? 'with its video' : 'without a picture'}',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: Builder(
                builder: (context) => EsplayMediaHero(
                  item: item,
                  unit: MediaQuery.sizeOf(context).width / 1920,
                  textInset: 88,
                  video: playing
                      ? Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFE040FB), Color(0xFF00BCD4)],
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(EsplayMediaHero)).height,
        EsplayMediaHero.heightFor(960 / 1920),
      );
      final shots = Platform.environment['SHOTS'];
      if (shots == null) return;
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/hero_${playing ? 'video' : 'plain'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
