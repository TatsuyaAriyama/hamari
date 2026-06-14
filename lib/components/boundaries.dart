import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../theme/palette.dart';

/// プレイフィールドの床と左右の壁（静的ボディ）。
/// 上端は開いており、ピースはそこから落ちてくる。
class Boundaries extends BodyComponent {
  Boundaries({required this.fieldSize})
      : super(
          paint: Paint()..color = HamariPalette.aiDeep,
          renderBody: false,
        );

  /// フィールドの内寸（メートル）。原点(0,0)が左上、yは下向き。
  final Vector2 fieldSize;

  @override
  Body createBody() {
    final w = fieldSize.x;
    final h = fieldSize.y;

    final bodyDef = BodyDef(
      type: BodyType.static,
      position: Vector2.zero(),
    );
    final body = world.createBody(bodyDef);

    // 床
    _edge(body, Vector2(0, h), Vector2(w, h));
    // 左壁
    _edge(body, Vector2(0, 0), Vector2(0, h));
    // 右壁
    _edge(body, Vector2(w, 0), Vector2(w, h));

    return body;
  }

  void _edge(Body body, Vector2 a, Vector2 b) {
    final shape = EdgeShape()..set(a, b);
    body.createFixture(
      FixtureDef(shape, friction: 0.6, restitution: 0.0),
    );
  }

  @override
  void render(Canvas canvas) {
    // 床・壁を控えめな線で示す。renderTree が body 変換（原点）を適用済み。
    final paintLine = Paint()
      ..color = HamariPalette.aiMid.withValues(alpha: 0.5)
      ..strokeWidth = 0.04
      ..style = PaintingStyle.stroke;
    final w = fieldSize.x;
    final h = fieldSize.y;
    canvas.drawLine(Offset(0, h), Offset(w, h), paintLine);
    canvas.drawLine(const Offset(0, 0), Offset(0, h), paintLine);
    canvas.drawLine(Offset(w, 0), Offset(w, h), paintLine);
  }
}
