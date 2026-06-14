import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamari/components/piece.dart';

/// 各ピース形状の凸多角形が Box2D の fixture として受理されることを検証する。
/// （凹形状の分解ミスや極小ポリゴンは PolygonShape.set で弾かれるため、
///  ここを通れば物理ワールドで安全に生成できる。）
void main() {
  final shapes = <PieceShape>[
    PieceShapes.square(),
    PieceShapes.tab(),
    PieceShapes.notch(),
    PieceShapes.bar(),
    PieceShapes.lShape(),
  ];

  for (final shape in shapes) {
    test('shape "${shape.id}" builds valid convex fixtures', () {
      final world = World(Vector2(0, 10));
      final body = world.createBody(
        BodyDef(type: BodyType.dynamic, position: Vector2.zero()),
      );

      expect(shape.polygons, isNotEmpty);
      for (final poly in shape.polygons) {
        expect(poly.length, greaterThanOrEqualTo(3));
        final s = PolygonShape()..set(poly.map((v) => v.clone()).toList());
        // 受理された頂点が3つ以上あること（縮退していない）。
        expect(s.vertices.length, greaterThanOrEqualTo(3));
        body.createFixture(FixtureDef(s, density: 1.0));
      }

      expect(body.fixtures.length, shape.polygons.length);
      // 1ステップ回して NaN 等の破綻が出ないこと。
      world.stepDt(1 / 60);
      expect(body.position.x.isFinite, isTrue);
      expect(body.position.y.isFinite, isTrue);
    });
  }
}
