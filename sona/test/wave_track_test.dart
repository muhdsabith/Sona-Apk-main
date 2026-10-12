import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sona/ui/olam_theme.dart';
import 'package:sona/ui/wave_track.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('Wave seek control is interactive in $direction', (
      tester,
    ) async {
      var position = 0.25;
      await tester.pumpWidget(
        MaterialApp(
          theme: olamTheme(),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Center(
                  child: SizedBox(
                    width: 300,
                    child: SliderTheme(
                      data: SliderTheme.of(
                        context,
                      ).copyWith(trackShape: const WaveTrack()),
                      child: Slider(
                        value: position,
                        onChanged: (value) => setState(() => position = value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(Slider));
      final x = direction == TextDirection.ltr ? box.right - 40 : box.left + 40;
      await tester.tapAt(Offset(x, box.center.dy));
      await tester.pumpAndSettle();
      expect(position, greaterThan(0.5));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Unavailable seek control stays disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: olamTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => SliderTheme(
              data: SliderTheme.of(
                context,
              ).copyWith(trackShape: const WaveTrack()),
              child: const Slider(value: 0, onChanged: null),
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(tester.takeException(), isNull);
  });
}
