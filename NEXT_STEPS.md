# Hamari — 次にやること / ハンドオフ

別マシン・別セッションからこのリポジトリを開いた人（含む将来の自分／Claude）が、
文脈ゼロから作業を再開できるようにするためのドキュメント。

---

## 1. 現状サマリ

**実装済み（MVP 着手順 1〜4 = コアゲームプレイ＋噛み合い消滅）**
- `lib/game/hamari_game.dart` — Forge2DGame本体、カメラ合わせ、着地ロック→出現ループ、入力API、**着地時の噛み合い判定→消滅・加点（`score`）**
- `lib/components/boundaries.dart` — 床・左右の壁（静的ボディ、上端は開放）
- `lib/components/piece.dart` — 凹凸ピース（Box2Dの制約上、複数の凸fixtureの合成）＋藍の描画。形状5種（square / tab / notch / bar / L）。**tab/notch にコネクタ・メタデータ付与＋消滅フェード**
- `lib/components/spawn_controller.dart` — 現在ピース＋ネクスト管理
- `lib/components/input_layer.dart` — タップ=回転(30°) / 横ドラッグ=移動 / 下スワイプ=即落下
- `lib/systems/match_resolver.dart` — **噛み合い判定の純モジュール（forge2d非依存）。コネクタ・面積フィット誤差・凸×凸交差(Sutherland–Hodgman)・shoelace**
- `lib/theme/palette.dart` — 藍の階調
- `test/piece_shapes_test.dart` — 全形状の凸fixtureがBox2Dに受理されるか検証
- `test/match_resolver_test.dart` — **判定の5系統（完全一致／ε境界／過／不足／非対応姿勢）＋ε スイープ＋剛体変換**
- `test/widget_test.dart` — 起動スモーク

**検証済み（着手順1〜3まで。着手順4は ⚠️ 未検証）**
- `flutter analyze` → No issues
- `flutter test` → 6件パス
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED（Dartコードはコンパイル可能）
- ⚠️ **着手順4の追加分（match_resolver / 新テスト / piece・game の変更）は Flutter ツールチェーンの無い環境で書いたため `analyze`/`test` 未実行。別マシンで最初に `flutter test` を回して緑を確認すること。**

**未実装（このあと）**
- 着手順5: ネクスト表示UI・危険ライン・ゲームオーバー ← **次の作業**
- 着手順6: タイトル／結果／設定の各画面 ＋ riverpod ＋ ハイスコア保存(shared_preferences)
- 着手順7: デザインシステム適用・音(flame_audio)・触覚(HapticFeedback)
- 着手順8: iOS提出準備（権限なし確認・App Privacy・レーティング・スクショ）
- 残課題（着手順4の仕上げ）: **実機で `ε`（既定0.18）を手触り調整**。tab/notch 以外の形状にもコネクタを付けるか検討。消滅時の物理（フェード中は当たり判定が残る）を詰めるか検討。

---

## 2. 別マシンでのセットアップ

```bash
git clone https://github.com/TatsuyaAriyama/hamari.git
cd hamari
flutter pub get
flutter precache --ios      # iOSエンジンartifactsが未取得だと build/run が失敗する
flutter test                # まず緑を確認
flutter run                 # 実機/シミュレータで起動
```

### ⚠️ 既知の環境ブロッカー（このプロジェクトを最初に作ったMac固有の可能性大）

そのMacでは `flutter run` / `flutter build ios` が **`Flutter.framework` のアドホック署名**で失敗した：
```
Failed to codesign .../Flutter.framework/Flutter with identity -
resource fork, Finder information, or similar detritus not allowed
```
- **原因**: そのmacOSが新規作成ファイル全てに `com.apple.provenance` 拡張属性を自動付与し、
  `codesign` のバンドル署名がそれを「detritus」として拒否する。`xattr -c`/`-d` では除去不可。
- **コードの問題ではない**（analyze/test/直接xcodebuildは通る）。**その環境固有**。
- **別マシンでは発生しない可能性が高い** → まず普通に `flutter run` を試す。
- 再発した場合の調査は深掘り済み。同じ轍を踏まないこと（標準のxattr除去は効かない）。

---

## 3. 着手順4：`match_resolver`（実装済み・要実機調整）

設計判断は **`docs/adr/ADR-001-match-resolver.md`**（Status: Accepted）。要点：
**コネクタ・メタデータ(broad-phase) ＋ 凸ポリゴンの面積フィット誤差(narrow-phase) を単一しきい値 ε で判定する純関数。物理から切り離してテスト可能にする。**

### 実装チェックリスト（ADR-001 の Action Items）
1. [x] `PieceShape`（`lib/components/piece.dart`）に `connectors`（type=tab/pocket, polygon, 向き）を追加。tab/notch に付与済み
2. [x] `lib/systems/match_resolver.dart` を **forge2d非依存の純モジュール**として新規作成
3. [x] 幾何ヘルパ：凸×凸交差（Sutherland–Hodgman）＋多角形面積（shoelace）
4. [x] しきい値 `ε`・broad-phase姿勢許容を `MatchConfig` に定数化（既定 ε=0.18 / 姿勢許容18°）
5. [x] 着地ロック時（`hamari_game.dart` `_resolveMatches`）に近接ペアを集めて resolver 呼び出し → 成立で両ピースをフェード除去・加点（`score`）
6. [x] ユニットテスト：完全一致／ε境界のズレ／過(はみ出し)／不足(隙間)／非対応姿勢 の5系統＋ε スイープ（`test/match_resolver_test.dart`）
7. [ ] **実機で ε を調整（体験の生命線。残課題）**。tab/notch 以外へのコネクタ付与は未着手

### 判定の式（ADRより／実装と一致）
- tab と pocket をワールド座標へ写像（`WorldConnector.from(position, angle)`）
- `seated = area(tab ∩ pocket)`
- `fitError = (area(tab) − seated) + (area(pocket) − seated)`  ← 第1項=過(overflow)、第2項=不足(gap)
- `fitError / area(pocket) < ε` で成立。加えて broad-phase で両法線が向かい合う(≈180°)こと

### 設計上の注意（実装で判明）
- tab の出っ張りと notch の切り欠きは **同寸（幅0.64×深さ0.55）** に揃えてあるので、ぴたり重なれば `fitError≈0`。notch の柱は深さ0.55へ更新済み（旧0.55スロット浅め→修正）。
- コネクタは **物理fixtureとは別管理のメタデータ**。形状を変えたら両方更新が必要（二重管理）。
- 消滅は `Piece.dissolve()` → 0.25秒フェード → `removeFromParent()`。**フェード中も当たり判定は残る**（forge2d 0.14 の active/enabled API差異を避けたため）。気になるなら後で sensor 化を検討。

---

## 4. 調整ノブ（`lib/game/hamari_game.dart` の定数）

| 定数 | 現在値 | 意味 |
|------|--------|------|
| `_gravityY` | 22.0 | 重力（落下速度の体感） |
| `rotationStepDegrees` | 30.0 | 回転刻み（独自性のため30°採用。テトリス回避＋判定が破綻しない離散スナップ） |
| `_instantDropSpeed` | 30.0 | 下スワイプ即落下の速度 |
| `_restSpeed` | 0.28 | 着地とみなす速度しきい値 |
| `_settleTime` | 0.45 | 静止継続→固定までの秒数 |
| `_minAgeToLock` | 0.35 | 生成直後の誤固定を防ぐ猶予 |
| `fieldSize` | 7.2 × 13.0 | フィールド内寸（メートル。原点左上・y下向き） |
| `_matchConfig.epsilon` | 0.18 | **噛み合い許容（生命線）。相対面積誤差の上限**。`match_resolver.dart` の `MatchConfig` |
| `_matchConfig.normalToleranceDegrees` | 18.0 | broad-phase：法線が向かい合うとみなす角度許容（30°スナップの隣を弾く） |
| `_matchProximity` | 2.4 | 噛み合い候補にする近接距離（m） |
| `_matchScore` | 100 | 1ペア消滅あたりの加点 |

---

## 5. 設計メモ・前提
- ピースは **凸fixtureの合成**で凹を表現（Box2Dは凹fixture不可）。notch=3分割、形状定義は `piece.dart`。
- 入力は flame の **モダンなイベント系**（TapCallbacks/DragCallbacks）。旧 `TapDetector`/`PanDetector` は非推奨なので使わない。
- 状態管理: 画面跨ぎ（ハイスコア・設定・現在スコア）のみ riverpod、ゲーム内物理状態は Flame 側。混ぜない（spec方針）。
- スコープ判断: MVPは「落として・噛み合わせて・消す」一本。連鎖/色マッチ/日替わりお題は v1 に温存。
