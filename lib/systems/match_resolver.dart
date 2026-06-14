import 'dart:math' as math;

// Vector2 は flame（forge2d ではない直接依存）経由で取得する。
// このモジュールは forge2d / 物理ワールドに一切依存せず、純粋な幾何だけで
// 噛み合いを判定する（ADR-001：テスト容易性の要件）。
import 'package:flame/components.dart';

/// コネクタの種別。
/// - [tab]    = 凸の出っ張り（ポリゴンそのもの）
/// - [pocket] = 凹の空き領域（ネガティブスペースのポリゴン）
enum ConnectorType { tab, pocket }

/// ピース形状に付与する噛み合いコネクタ（ローカル座標・メートル）。
///
/// ピースの物理 fixture とは別管理の「メタデータ」。`PieceShape` がこれを持ち、
/// 着地時に [WorldConnector.from] でワールドへ写してから [MatchResolver] に渡す。
class Connector {
  const Connector({
    required this.type,
    required this.polygon,
    required this.normal,
  });

  final ConnectorType type;

  /// 凸多角形（ローカル座標）。tab=出っ張り、pocket=空きスロット。
  final List<Vector2> polygon;

  /// コネクタが開く向き（ローカル・単位ベクトル）。
  /// 噛み合う相手とは broad-phase でこの法線が「向かい合う」ことを要求する。
  final Vector2 normal;
}

/// ワールド座標へ写したコネクタ。[MatchResolver.evaluate] の入力。
class WorldConnector {
  WorldConnector({
    required this.type,
    required this.polygon,
    required this.normal,
  });

  final ConnectorType type;
  final List<Vector2> polygon;
  final Vector2 normal;

  /// ローカルコネクタを剛体変換（位置＋角度）でワールドへ写す。forge2d 非依存。
  factory WorldConnector.from(
    Connector c, {
    required Vector2 position,
    required double angle,
  }) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final poly = <Vector2>[];
    for (final v in c.polygon) {
      // 回転してから平行移動。
      final x = v.x * cos - v.y * sin;
      final y = v.x * sin + v.y * cos;
      poly.add(Vector2(position.x + x, position.y + y));
    }
    final normal =
        Vector2(c.normal.x * cos - c.normal.y * sin,
            c.normal.x * sin + c.normal.y * cos)
          ..normalize();
    return WorldConnector(type: c.type, polygon: poly, normal: normal);
  }
}

/// 噛み合い判定のしきい値。`epsilon` が体験の生命線＝唯一の主要ノブ。
class MatchConfig {
  const MatchConfig({
    this.epsilon = 0.18,
    this.normalToleranceDegrees = 18.0,
  });

  /// 相対面積誤差 `fitError / area(pocket)` の許容上限。
  /// 小さいほど「ぴたり」を要求（厳しすぎ＝ストレス、緩すぎ＝単調）。
  final double epsilon;

  /// broad-phase：2つの法線を「向かい合う(180°)」とみなす角度許容（度）。
  /// 30°スナップの隣（30°ズレ）を弾けるよう 30°未満にする。
  final double normalToleranceDegrees;
}

/// 判定結果。診断値（過/不足/seated）も持つので ε チューニングに使える。
class MatchResult {
  const MatchResult({
    required this.matched,
    required this.seated,
    required this.overflow,
    required this.gap,
    required this.relativeError,
    required this.posed,
  });

  /// 成立したか（broad-phase 通過 かつ 相対誤差 < ε）。
  final bool matched;

  /// `area(tab ∩ pocket)` = 収まった面積。
  final double seated;

  /// 過：pocket からはみ出した tab の面積。
  final double overflow;

  /// 不足：埋まらなかった pocket の面積。
  final double gap;

  /// `fitError / area(pocket)`。
  final double relativeError;

  /// broad-phase（法線が向かい合う）を満たすか。
  final bool posed;

  double get fitError => overflow + gap;

  static const MatchResult none = MatchResult(
    matched: false,
    seated: 0,
    overflow: 0,
    gap: 0,
    relativeError: double.infinity,
    posed: false,
  );
}

/// 噛み合い判定の純関数群（forge2d 非依存）。
class MatchResolver {
  const MatchResolver._();

  /// 2つのワールドコネクタが噛み合うかを判定する。
  ///
  /// 手順（ADR-001）:
  /// 1. tab × pocket の対であること。
  /// 2. broad-phase：法線が向かい合う（dot ≈ -1）こと。
  /// 3. narrow-phase：`seated = area(tab ∩ pocket)` から過/不足を面積で測り、
  ///    `(overflow + gap) / area(pocket) < ε` で成立。
  static MatchResult evaluate(
    WorldConnector a,
    WorldConnector b, {
    MatchConfig config = const MatchConfig(),
  }) {
    final WorldConnector tab;
    final WorldConnector pocket;
    if (a.type == ConnectorType.tab && b.type == ConnectorType.pocket) {
      tab = a;
      pocket = b;
    } else if (a.type == ConnectorType.pocket && b.type == ConnectorType.tab) {
      tab = b;
      pocket = a;
    } else {
      return MatchResult.none; // tab×tab / pocket×pocket は不成立。
    }

    // broad-phase：法線の向かい合い。両者単位ベクトル前提で dot ≈ -1 を要求。
    final dot = tab.normal.dot(pocket.normal).clamp(-1.0, 1.0);
    final cosTol = math.cos(config.normalToleranceDegrees * math.pi / 180.0);
    final posed = dot <= -cosTol;

    // narrow-phase：面積フィット誤差。
    final pocketArea = polygonArea(pocket.polygon);
    if (pocketArea <= 0) return MatchResult.none;
    final tabArea = polygonArea(tab.polygon);
    final seated = polygonArea(convexIntersection(tab.polygon, pocket.polygon));
    final overflow = math.max(0.0, tabArea - seated);
    final gap = math.max(0.0, pocketArea - seated);
    final relativeError = (overflow + gap) / pocketArea;

    return MatchResult(
      matched: posed && relativeError < config.epsilon,
      seated: seated,
      overflow: overflow,
      gap: gap,
      relativeError: relativeError,
      posed: posed,
    );
  }
}

// ---- 幾何ヘルパ（純関数） ----

/// 多角形の符号付き面積（shoelace）。CCW で正、CW で負。
double polygonSignedArea(List<Vector2> p) {
  if (p.length < 3) return 0;
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].x * p[j].y - p[j].x * p[i].y;
  }
  return a / 2.0;
}

/// 多角形の面積（符号なし）。
double polygonArea(List<Vector2> p) => polygonSignedArea(p).abs();

/// 凸クリップ多角形 [clip] で [subject] をクリップした交差多角形を返す
/// （Sutherland–Hodgman）。[clip] は凸であること。空なら `[]`。
List<Vector2> convexIntersection(List<Vector2> subject, List<Vector2> clip) {
  if (subject.length < 3 || clip.length < 3) return const <Vector2>[];
  // クリップは CCW に正規化（内側判定の符号を一定にする）。
  final c =
      polygonSignedArea(clip) < 0 ? clip.reversed.toList(growable: false) : clip;

  var output = <Vector2>[for (final v in subject) v.clone()];
  for (var i = 0; i < c.length; i++) {
    if (output.isEmpty) break;
    final a = c[i];
    final b = c[(i + 1) % c.length];
    final input = output;
    output = <Vector2>[];
    for (var k = 0; k < input.length; k++) {
      final cur = input[k];
      final prev = input[(k - 1 + input.length) % input.length];
      final curInside = _leftOfOrOn(a, b, cur);
      final prevInside = _leftOfOrOn(a, b, prev);
      if (curInside) {
        if (!prevInside) {
          final x = _segIntersect(prev, cur, a, b);
          if (x != null) output.add(x);
        }
        output.add(cur.clone());
      } else if (prevInside) {
        final x = _segIntersect(prev, cur, a, b);
        if (x != null) output.add(x);
      }
    }
  }
  return output;
}

/// 有向辺 a→b に対して点 p が左側（CCW で内側）または辺上にあるか。
bool _leftOfOrOn(Vector2 a, Vector2 b, Vector2 p) =>
    (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= -1e-9;

/// 線分 p1→p2 と 直線 a→b の交点（平行なら null）。
Vector2? _segIntersect(Vector2 p1, Vector2 p2, Vector2 a, Vector2 b) {
  final rx = p2.x - p1.x;
  final ry = p2.y - p1.y;
  final sx = b.x - a.x;
  final sy = b.y - a.y;
  final denom = rx * sy - ry * sx;
  if (denom.abs() < 1e-12) return null;
  final t = ((a.x - p1.x) * sy - (a.y - p1.y) * sx) / denom;
  return Vector2(p1.x + t * rx, p1.y + t * ry);
}
