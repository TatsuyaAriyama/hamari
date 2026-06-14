import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../game/hamari_game.dart';

/// フィールド全体を覆う透明な入力層。
/// タップ＝回転、横ドラッグ＝移動、下スワイプ＝即落下を [HamariGame] に伝える。
///
/// ワールド座標系（1単位=1m）に置くので、ドラッグの localDelta は
/// そのままメートル単位の移動量になる。
class InputLayer extends PositionComponent
    with TapCallbacks, DragCallbacks, HasGameReference<HamariGame> {
  InputLayer({required Vector2 fieldSize})
      : super(size: fieldSize, position: Vector2.zero());

  @override
  void onTapUp(TapUpEvent event) {
    game.rotateActive();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    game.moveActive(event.localDelta.x);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final v = event.velocity;
    // 下方向に速いスワイプ → 即落下（velocity は px/sec）。
    if (v.y > 600 && v.y.abs() > v.x.abs()) {
      game.dropActive();
    }
  }
}
