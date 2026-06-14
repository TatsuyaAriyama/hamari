import 'package:flutter/painting.dart';

/// 嵌（Hamari）の配色。kasane 系の藍の階調を継承する。
/// 色そのものはマッチ条件にしない（MVPは形だけで判定）。
class HamariPalette {
  HamariPalette._();

  /// 地（生成り）
  static const Color ground = Color(0xFFF4F0E6);

  /// 文字・輪郭（墨）
  static const Color sumi = Color(0xFF2B2B2B);

  /// 藍・淡（淡縹）
  static const Color aiLight = Color(0xFFAEB4C8);

  /// 藍・中（縹）
  static const Color aiMid = Color(0xFF525F86);

  /// 藍・深（留紺）
  static const Color aiDeep = Color(0xFF2A3252);

  /// ピースに巡回で割り当てる藍3段。
  static const List<Color> pieceFills = <Color>[aiLight, aiMid, aiDeep];
}
