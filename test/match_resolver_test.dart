import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamari/systems/match_resolver.dart';

/// 中心 (cx,cy)・半幅 hw・半高 hh の矩形（ワールド/ローカル共通ヘルパ）。
List<Vector2> rect(double cx, double cy, double hw, double hh) => <Vector2>[
      Vector2(cx - hw, cy - hh),
      Vector2(cx + hw, cy - hh),
      Vector2(cx + hw, cy + hh),
      Vector2(cx - hw, cy + hh),
    ];

WorldConnector tab(List<Vector2> poly, {Vector2? normal}) => WorldConnector(
      type: ConnectorType.tab,
      polygon: poly,
      normal: (normal ?? Vector2(0, -1))..normalize(),
    );

WorldConnector pocket(List<Vector2> poly, {Vector2? normal}) => WorldConnector(
      type: ConnectorType.pocket,
      polygon: poly,
      // 既定は tab(上向き) と向かい合う下向き。
      normal: (normal ?? Vector2(0, 1))..normalize(),
    );

void main() {
  // 共通寸法：幅0.64・高さ0.55（piece.dart の tab/notch と同寸）。
  const hw = 0.32;
  const hh = 0.275;
  final area = (2 * hw) * (2 * hh); // 0.352

  group('幾何ヘルパ', () {
    test('shoelace 面積（単位正方形 = 1）', () {
      expect(polygonArea(rect(0, 0, 0.5, 0.5)), closeTo(1.0, 1e-9));
    });

    test('巻き方向に依らず面積は正', () {
      final cw = rect(0, 0, 0.5, 0.5).reversed.toList();
      expect(polygonArea(cw), closeTo(1.0, 1e-9));
    });

    test('凸×凸交差（半分重なる正方形 → 重なりの面積）', () {
      final a = rect(1, 1, 1, 1); // [0,0]..[2,2]
      final b = rect(2, 2, 1, 1); // [1,1]..[3,3]
      expect(polygonArea(convexIntersection(a, b)), closeTo(1.0, 1e-9));
    });

    test('重ならない多角形の交差は空', () {
      final a = rect(0, 0, 0.5, 0.5);
      final b = rect(5, 5, 0.5, 0.5);
      expect(convexIntersection(a, b), isEmpty);
    });
  });

  group('MatchResolver — 5系統', () {
    // (1) 完全一致：tab と pocket が同位置・同寸・法線対向。
    test('完全一致 → 成立、fitError≈0', () {
      final r = MatchResolver.evaluate(
        tab(rect(0, 0, hw, hh)),
        pocket(rect(0, 0, hw, hh)),
      );
      expect(r.posed, isTrue);
      expect(r.seated, closeTo(area, 1e-9));
      expect(r.fitError, closeTo(0.0, 1e-9));
      expect(r.relativeError, closeTo(0.0, 1e-9));
      expect(r.matched, isTrue);
    });

    // (2) 僅かなズレ（ε境界）：横シフト d で relativeError = 2d/幅。
    test('僅かなズレ → ε 境界で成否が切り替わる', () {
      // d=0.05 → rel = 2*0.05/0.64 = 0.15625
      final near = MatchResolver.evaluate(
        tab(rect(0.05, 0, hw, hh)),
        pocket(rect(0, 0, hw, hh)),
      );
      expect(near.relativeError, closeTo(0.15625, 1e-9));
      expect(near.matched, isTrue); // 既定 ε=0.18 では成立

      // d=0.07 → rel = 0.21875 > 0.18 → 不成立
      final far = MatchResolver.evaluate(
        tab(rect(0.07, 0, hw, hh)),
        pocket(rect(0, 0, hw, hh)),
      );
      expect(far.relativeError, closeTo(0.21875, 1e-9));
      expect(far.matched, isFalse);
    });

    // (3) 過（はみ出し）：tab が pocket より大きい → overflow が支配。
    test('過（はみ出し） → overflow>0・gap≈0・不成立', () {
      final r = MatchResolver.evaluate(
        tab(rect(0, 0, 0.40, hh)), // 幅広タブ
        pocket(rect(0, 0, hw, hh)),
      );
      expect(r.seated, closeTo(area, 1e-9)); // pocket は完全に埋まる
      expect(r.gap, closeTo(0.0, 1e-9));
      expect(r.overflow, greaterThan(0.0));
      expect(r.matched, isFalse); // rel = 0.088/0.352 = 0.25
      expect(r.relativeError, closeTo(0.25, 1e-9));
    });

    // (4) 不足（隙間）：tab が pocket より小さい → gap が支配。
    test('不足（隙間） → gap>0・overflow≈0・不成立', () {
      final r = MatchResolver.evaluate(
        tab(rect(0, 0, 0.24, hh)), // 幅狭タブ
        pocket(rect(0, 0, hw, hh)),
      );
      expect(r.overflow, closeTo(0.0, 1e-9));
      expect(r.gap, greaterThan(0.0));
      expect(r.matched, isFalse);
      expect(r.relativeError, closeTo(0.25, 1e-9));
    });

    // (5) 非対応姿勢：面積は完全一致でも法線が向かい合わなければ不成立。
    test('非対応姿勢（法線が同方向） → broad-phase で棄却', () {
      final r = MatchResolver.evaluate(
        tab(rect(0, 0, hw, hh), normal: Vector2(0, -1)),
        pocket(rect(0, 0, hw, hh), normal: Vector2(0, -1)), // 対向していない
      );
      expect(r.relativeError, closeTo(0.0, 1e-9)); // 面積的には完璧
      expect(r.posed, isFalse);
      expect(r.matched, isFalse);
    });

    test('tab×tab / pocket×pocket は常に不成立', () {
      final tt = MatchResolver.evaluate(
        tab(rect(0, 0, hw, hh)),
        tab(rect(0, 0, hw, hh)),
      );
      final pp = MatchResolver.evaluate(
        pocket(rect(0, 0, hw, hh)),
        pocket(rect(0, 0, hw, hh)),
      );
      expect(tt.matched, isFalse);
      expect(pp.matched, isFalse);
    });
  });

  group('ε スイープ（同一配置で閾値だけ動かす）', () {
    // d=0.05 → rel≈0.15625 を境に ε で成否が変わることを確認。
    final r = MatchResolver.evaluate(
      tab(rect(0.05, 0, hw, hh)),
      pocket(rect(0, 0, hw, hh)),
    );

    for (final eps in <double>[0.05, 0.10, 0.15]) {
      test('ε=$eps（< rel）→ 不成立', () {
        final m = MatchResolver.evaluate(
          tab(rect(0.05, 0, hw, hh)),
          pocket(rect(0, 0, hw, hh)),
          config: MatchConfig(epsilon: eps),
        );
        expect(m.matched, isFalse, reason: 'rel=${r.relativeError}');
      });
    }

    for (final eps in <double>[0.18, 0.25, 0.40]) {
      test('ε=$eps（> rel）→ 成立', () {
        final m = MatchResolver.evaluate(
          tab(rect(0.05, 0, hw, hh)),
          pocket(rect(0, 0, hw, hh)),
          config: MatchConfig(epsilon: eps),
        );
        expect(m.matched, isTrue, reason: 'rel=${r.relativeError}');
      });
    }
  });

  group('WorldConnector.from（剛体変換）', () {
    // notch の pocket（角度0）に、180°回転した tab の出っ張りが噛み合う。
    test('180°回した tab が上向き pocket にぴたり嵌まる', () {
      const tabLocal = (0.0, -0.875); // tab() の出っ張り中心
      const pocketLocal = (0.0, -0.325); // notch() のスロット中心

      final pocketConn = Connector(
        type: ConnectorType.pocket,
        polygon: rect(pocketLocal.$1, pocketLocal.$2, hw, hh),
        normal: Vector2(0, -1),
      );
      final tabConn = Connector(
        type: ConnectorType.tab,
        polygon: rect(tabLocal.$1, tabLocal.$2, hw, hh),
        normal: Vector2(0, -1),
      );

      // pocket ピースを (3.6,6.0)・角度0 に配置。
      final pocketWorld = WorldConnector.from(
        pocketConn,
        position: Vector2(3.6, 6.0),
        angle: 0,
      );
      // tab ピースを 180°回し、出っ張りが pocket スロットへ重なる位置へ。
      // 回転後 tab 中心の相対位置は (0,+0.875) なので body は pocket中心-0.875。
      final tabWorld = WorldConnector.from(
        tabConn,
        position: Vector2(3.6, 6.0 + pocketLocal.$2 - 0.875),
        angle: math.pi,
      );

      final r = MatchResolver.evaluate(tabWorld, pocketWorld);
      expect(r.posed, isTrue);
      expect(r.relativeError, closeTo(0.0, 1e-6));
      expect(r.matched, isTrue);
    });
  });
}
