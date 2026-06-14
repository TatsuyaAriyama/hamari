import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../components/boundaries.dart';
import '../components/input_layer.dart';
import '../components/piece.dart';
import '../components/spawn_controller.dart';
import '../theme/palette.dart';

/// 嵌（Hamari）コア。落として・動かして・積み上げるところまで。
///
/// 噛み合い判定・消滅・スコア・ゲームオーバーは次パス。
class HamariGame extends Forge2DGame {
  HamariGame()
      : super(
          gravity: Vector2(0, _gravityY),
          zoom: 10,
        );

  // ---- 調整パラメータ（プロトで触って決める）----

  /// 重力（下向き m/s^2）。
  static const double _gravityY = 22.0;

  /// 回転の刻み（度）。独自性のため30度（12方位）を採用。
  /// テトリスの90度を避けつつ、離散スナップで判定を破綻させない。
  static const double rotationStepDegrees = 30.0;

  /// 即落下時の下向き速度（m/s）。
  static const double _instantDropSpeed = 30.0;

  /// 着地とみなす速度しきい値（m/s）。
  static const double _restSpeed = 0.28;

  /// 静止が続いて固定するまでの時間（秒）。
  static const double _settleTime = 0.45;

  /// 生成直後に固定判定しない猶予（秒）。
  static const double _minAgeToLock = 0.35;

  /// フィールド内寸（メートル）。原点(0,0)が左上、yは下向き。
  final Vector2 fieldSize = Vector2(7.2, 13.0);

  late final SpawnController spawner;

  /// 現在プレイヤーが操作中のピース。
  Piece? activePiece;

  bool _spawning = false;

  @override
  Color backgroundColor() => HamariPalette.ground;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // カメラをフィールド全体に合わせる。
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.position = fieldSize / 2;
    final fit = min(size.x / fieldSize.x, size.y / fieldSize.y);
    camera.viewfinder.zoom = fit * 0.92;

    await world.add(Boundaries(fieldSize: fieldSize));
    await world.add(InputLayer(fieldSize: fieldSize));

    spawner = SpawnController(
      spawnPosition: Vector2(fieldSize.x / 2, 0.9),
    );
    add(spawner);

    _spawnNext();
  }

  void _spawnNext() {
    if (_spawning) return;
    _spawning = true;
    final piece = spawner.takeNext();
    activePiece = piece;
    world.add(piece);
    _spawning = false;
  }

  @override
  void update(double dt) {
    super.update(dt);

    final piece = activePiece;
    if (piece == null) {
      _spawnNext();
      return;
    }
    if (!piece.isMounted) return;

    // 着地（静止）判定 → 固定して次へ。
    final speed = piece.body.linearVelocity.length;
    if (piece.age > _minAgeToLock && speed < _restSpeed) {
      piece.restTimer += dt;
    } else {
      piece.restTimer = 0;
    }

    if (piece.restTimer >= _settleTime) {
      piece.controllable = false;
      activePiece = null;
    }
  }

  // ---- 入力（InputLayer から呼ばれる）----

  bool get _hasActive =>
      activePiece != null && activePiece!.isMounted && activePiece!.controllable;

  /// 30度刻みで回転。
  void rotateActive() {
    if (!_hasActive) return;
    final p = activePiece!;
    final step = rotationStepDegrees * pi / 180.0;
    p.body.setTransform(p.body.position, p.body.angle + step);
    p.body.setAwake(true);
  }

  /// 横移動（dx はメートル）。
  void moveActive(double dx) {
    if (!_hasActive) return;
    final p = activePiece!;
    const inset = 0.7; // 壁にめり込まないための余白
    final newX =
        (p.body.position.x + dx).clamp(inset, fieldSize.x - inset);
    p.body.setTransform(Vector2(newX, p.body.position.y), p.body.angle);
    p.body.setAwake(true);
  }

  /// 即落下。
  void dropActive() {
    if (!_hasActive) return;
    final p = activePiece!;
    p.body.linearVelocity = Vector2(0, _instantDropSpeed);
    p.body.setAwake(true);
  }
}
