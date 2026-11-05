// T19 (03-ink 6.13-1, 6.12 R9): the scale bucket — the smallest bucket at or
// above the device scale, none (vector only) above the largest — and what
// setViewport makes of it (renderStats.currentBucket, no notification).
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/raster_tiles.dart';
import 'package:ink_engine/testing.dart';

const _buckets = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scaleBucketFor', () {
    test('the smallest bucket >= deviceScale', () {
      final cases = <double, double?>{
        0.1: 0.5,
        0.5: 0.5,
        0.51: 1.0,
        1.0: 1.0,
        1.0079: 1.5, // A4 595.28 pt in a 600 px view at DPR 1
        1.5: 1.5,
        1.75: 2.0,
        2.0: 2.0,
        2.0159: 3.0, // the same view at DPR 2
        2.9: 3.0,
        3.0: 3.0,
        3.0001: 4.0,
        4.0: 4.0,
      };
      for (final MapEntry(key: scale, value: bucket) in cases.entries) {
        expect(scaleBucketFor(_buckets, scale), bucket, reason: '$scale');
      }
    });

    test('above the largest → null (vector chunks only)', () {
      for (final scale in [4.0001, 5.0, 12.0, 1e9]) {
        expect(scaleBucketFor(_buckets, scale), isNull, reason: '$scale');
      }
    });

    test('a rounding error does not skip a bucket', () {
      expect(scaleBucketFor(_buckets, 2.0 + 1e-12), 2.0);
      expect(scaleBucketFor(_buckets, 0.1 * 3 * 10 / 3), 1.0);
      expect(scaleBucketFor(_buckets, 2.0 + 1e-6), 3.0);
    });

    test('not a positive finite device scale → null', () {
      for (final scale in [
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(scaleBucketFor(_buckets, scale), isNull, reason: '$scale');
      }
    });

    test('bucket order does not matter; bad buckets are ignored', () {
      const shuffled = [3.0, 0.5, 4.0, 1.5, 1.0, 2.0];
      for (final scale in [0.3, 0.9, 1.2, 1.9, 2.5, 3.5, 4.5]) {
        expect(
          scaleBucketFor(shuffled, scale),
          scaleBucketFor(_buckets, scale),
          reason: '$scale',
        );
      }
      expect(scaleBucketFor([double.nan, -2, 0, 2, double.infinity], 1), 2);
      expect(scaleBucketFor(const [], 1), isNull);
    });
  });

  group('setViewport → renderStats.currentBucket', () {
    late InkPageController controller;
    var notified = 0;

    setUp(() {
      notified = 0;
      controller = createTestPageController(
        config: const InkRenderConfig(rasterTiles: false),
      )..updateContent(SyntheticInk.pageContent());
      controller.addListener(() => notified++);
    });
    tearDown(() => controller.dispose());

    test('null before the first report (first frame draws vectors)', () {
      expect(controller.renderStats.currentBucket, isNull);
    });

    test('follows the device scale; no notification', () {
      final cases = <double, double?>{
        1.0: 1.0,
        2.0159: 3.0,
        0.4: 0.5,
        4.2: null,
        3.9: 4.0,
      };
      for (final MapEntry(key: scale, value: bucket) in cases.entries) {
        controller.setViewport(deviceScale: scale, isScaling: false);
        expect(controller.renderStats.currentBucket, bucket, reason: '$scale');
      }
      controller.setViewport(
        visiblePageRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        deviceScale: 2,
        isScaling: true,
      );
      expect(controller.renderStats.currentBucket, 2.0);
      expect(notified, 0);
    });

    test('the controller config buckets are used', () {
      final c = createTestPageController(
        config: const InkRenderConfig(rasterTiles: false, scaleBuckets: [1, 8]),
      )..updateContent(SyntheticInk.pageContent());
      addTearDown(c.dispose);
      c.setViewport(deviceScale: 5, isScaling: false);
      expect(c.renderStats.currentBucket, 8.0);
      c.setViewport(deviceScale: 0.5, isScaling: false);
      expect(c.renderStats.currentBucket, 1.0);
      c.setViewport(deviceScale: 9, isScaling: false);
      expect(c.renderStats.currentBucket, isNull);
    });
  });
}
