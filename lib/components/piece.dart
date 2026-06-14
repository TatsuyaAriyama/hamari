import 'dart:math';
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../systems/match_resolver.dart';
import '../theme/palette.dart';

/// ピースの形状定義。
///
/// Box2D の fixture は凸多角形しか持てないため、凹を含む形は
/// 複数の凸多角形（[polygons]）の合成として表現する。
/// 座標はローカル（メートル）。原点はおおよそ重心。
class PieceShape {
  const PieceShape(this.id, this.polygons,
      {this.connectors = const <Connector>[]});

  final String id;

  /// 凸多角形のリスト。各多角形は頂点（ローカル座標）のリスト。
  final List<List<Vector2>> polygons;

  /// 噛み合い判定用のコネクタ（tab/pocket）。物理 fixture とは別管理の
  /// メタデータで、持たない形状（square/bar/L）は空。
  final List<Connector> connectors;
}

/// 形状ファクトリ。Vector2 が const にできないため都度生成する。
class PieceShapes {
  PieceShapes._();

  static const double _u = 0.6; // 基本ユニット半径（m）

  static List<Vector2> _rect(double cx, double cy, double hw, double hh) {
    return <Vector2>[
      Vector2(cx - hw, cy - hh),
      Vector2(cx + hw, cy - hh),
      Vector2(cx + hw, cy + hh),
      Vector2(cx - hw, cy + hh),
    ];
  }

  /// ただの正方形。
  static PieceShape square() => PieceShape('square', <List<Vector2>>[
        _rect(0, 0, _u, _u),
      ]);

  /// 凸：上に矩形のタブを持つ正方形。notch とぴたり噛み合う。
  /// y は負が上。タブ幅0.64・高さ0.55（= notch の切り欠きと同寸）。
  static PieceShape tab() => PieceShape('tab', <List<Vector2>>[
        _rect(0, 0, _u, _u),
        _rect(0, -_u - 0.275, 0.32, 0.275),
      ], connectors: <Connector>[
        // 出っ張りそのもの。法線は外（上＝-y）向き。
        Connector(
          type: ConnectorType.tab,
          polygon: _rect(0, -_u - 0.275, 0.32, 0.275),
          normal: Vector2(0, -1),
        ),
      ]);

  /// 凹：上中央に矩形の切り欠きを持つ正方形（3つの凸に分解）。
  /// 切り欠きは幅0.64・深さ0.55で、tab の出っ張りとぴたり一致する。
  static PieceShape notch() => PieceShape('notch', <List<Vector2>>[
        // 切り欠きより下の土台
        _rect(0, 0.275, _u, _u - 0.275),
        // 切り欠き左の柱（深さ0.55＝上端まで届く）
        _rect(-0.46, -0.325, 0.14, 0.275),
        // 切り欠き右の柱
        _rect(0.46, -0.325, 0.14, 0.275),
      ], connectors: <Connector>[
        // 空きスロット（ネガティブスペース）。開口は上（-y）向き。
        Connector(
          type: ConnectorType.pocket,
          polygon: _rect(0, -0.325, 0.32, 0.275),
          normal: Vector2(0, -1),
        ),
      ]);

  /// 横長のバー。
  static PieceShape bar() => PieceShape('bar', <List<Vector2>>[
        _rect(0, 0, _u * 1.5, _u * 0.5),
      ]);

  /// L 字（2つの矩形）。
  static PieceShape lShape() => PieceShape('L', <List<Vector2>>[
        _rect(-0.3, 0, 0.3, _u), // 縦の腕
        _rect(0.3, 0.3, 0.6, 0.3), // 下の腕
      ]);

  static final List<PieceShape Function()> _all = <PieceShape Function()>[
    square,
    tab,
    notch,
    bar,
    lShape,
  ];

  static final Random _rng = Random();

  static PieceShape random() => _all[_rng.nextInt(_all.length)]();
}

/// 落下・積み上がりするピース本体。複数の凸 fixture を1つのボディに持つ。
class Piece extends BodyComponent {
  Piece({
    required this.shape,
    required this.spawnPosition,
    required this.fillColor,
  }) : super(renderBody: false);

  final PieceShape shape;
  final Vector2 spawnPosition;
  final Color fillColor;

  /// プレイヤー操作の対象かどうか。着地して固定されたら false。
  bool controllable = true;

  /// 低速状態が続いた時間（着地判定用）。
  double restTimer = 0;

  /// 生成からの経過時間（生成直後の誤判定を防ぐ）。
  double age = 0;

  /// 噛み合いが成立して消滅中か。true の間フェードし、消えたら自分を除去する。
  bool matched = false;

  /// 消滅フェードの残り（1=不透明 → 0=消滅）。
  double _fade = 1.0;

  /// フェード速度（1/秒）。0.25秒で消える。
  static const double _fadeRate = 4.0;

  /// 噛み合い成立。フェードアウトを開始する（除去は [update] が行う）。
  void dissolve() => matched = true;

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      type: BodyType.dynamic,
      position: spawnPosition.clone(),
      // 高速落下時の貫通を抑える。
      bullet: true,
    );
    final body = world.createBody(bodyDef);

    for (final poly in shape.polygons) {
      final s = PolygonShape()..set(poly.map((v) => v.clone()).toList());
      body.createFixture(
        FixtureDef(
          s,
          density: 1.0,
          friction: 0.55,
          restitution: 0.0,
        ),
      );
    }
    return body;
  }

  @override
  void render(Canvas canvas) {
    // renderTree がボディの位置・角度を適用済み。ローカル（m）で描く。
    final alpha = matched ? _fade.clamp(0.0, 1.0) : 1.0;
    final fill = Paint()
      ..color = fillColor.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = HamariPalette.aiDeep.withValues(alpha: alpha)
      ..strokeWidth = 0.035
      ..style = PaintingStyle.stroke;

    for (final fixture in body.fixtures) {
      final s = fixture.shape;
      if (s is! PolygonShape) continue;
      final path = Path();
      final verts = s.vertices;
      for (var i = 0; i < verts.length; i++) {
        final v = verts[i];
        if (i == 0) {
          path.moveTo(v.x, v.y);
        } else {
          path.lineTo(v.x, v.y);
        }
      }
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    age += dt;
    if (matched) {
      _fade -= _fadeRate * dt;
      if (_fade <= 0) {
        removeFromParent(); // BodyComponent.onRemove がボディを破棄する。
      }
    }
  }
}
