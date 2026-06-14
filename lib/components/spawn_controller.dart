import 'package:flame/components.dart';

import 'piece.dart';
import '../theme/palette.dart';

/// ピースの出現を司る。現在のピースとネクスト1つを保持し、
/// 求められたらワールドに Piece を生成して返す。
///
/// 噛み合い判定や消滅はここでは扱わない（次パスの match_resolver 担当）。
class SpawnController extends Component {
  SpawnController({required this.spawnPosition});

  /// 出現位置（フィールド上端中央、メートル）。
  final Vector2 spawnPosition;

  /// 次に出てくる形。UI のネクスト表示にも使う。
  PieceShape next = PieceShapes.random();

  int _colorIndex = 0;

  /// ネクストを現在ピースとして生成し、新しいネクストを用意する。
  /// 生成した Piece を返す（呼び出し側がワールドへ add する）。
  Piece takeNext() {
    final shape = next;
    next = PieceShapes.random();
    final color = HamariPalette.pieceFills[_colorIndex % HamariPalette.pieceFills.length];
    _colorIndex++;
    return Piece(
      shape: shape,
      spawnPosition: spawnPosition.clone(),
      fillColor: color,
    );
  }
}
