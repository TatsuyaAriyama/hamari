# Hamari — 次にやること / ハンドオフ

別マシン・別セッションからこのリポジトリを開いた人（含む将来の自分／Claude）が、
文脈ゼロから作業を再開できるようにするためのドキュメント。

---

## 1. 現状サマリ

**実装済み（MVP 着手順 1〜3 = コアゲームプレイ）**
- `lib/game/hamari_game.dart` — Forge2DGame本体、カメラ合わせ、着地ロック→出現ループ、入力API
- `lib/components/boundaries.dart` — 床・左右の壁（静的ボディ、上端は開放）
- `lib/components/piece.dart` — 凹凸ピース（Box2Dの制約上、複数の凸fixtureの合成）＋藍の描画。形状5種（square / tab / notch / bar / L）
- `lib/components/spawn_controller.dart` — 現在ピース＋ネクスト管理
- `lib/components/input_layer.dart` — タップ=回転(30°) / 横ドラッグ=移動 / 下スワイプ=即落下
- `lib/theme/palette.dart` — 藍の階調
- `test/piece_shapes_test.dart` — 全形状の凸fixtureがBox2Dに受理されるか検証
- `test/widget_test.dart` — 起動スモーク

**検証済み**
- `flutter analyze` → No issues
- `flutter test` → 6件パス
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED（Dartコードはコンパイル可能）

**未実装（このあと）**
- 着手順4: 噛み合い判定 `match_resolver` ＋ 消滅・加点 ← **最優先・次の作業**
- 着手順5: ネクスト表示UI・危険ライン・ゲームオーバー
- 着手順6: タイトル／結果／設定の各画面 ＋ riverpod ＋ ハイスコア保存(shared_preferences)
- 着手順7: デザインシステム適用・音(flame_audio)・触覚(HapticFeedback)
- 着手順8: iOS提出準備（権限なし確認・App Privacy・レーティング・スクショ）

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

## 3. 次の作業：`match_resolver`（着手順4）

設計判断は **`docs/adr/ADR-001-match-resolver.md`** に記録済み。要点：
**コネクタ・メタデータ(broad-phase) ＋ 凸ポリゴンの面積フィット誤差(narrow-phase) を単一しきい値 ε で判定する純関数。物理から切り離してテスト可能にする。**

### 実装チェックリスト（ADR-001 の Action Items 再掲）
1. [ ] `PieceShape`（`lib/components/piece.dart`）に `connectors`（type=tab/pocket, polygon, 向き）を追加
2. [ ] `lib/systems/match_resolver.dart` を **forge2d非依存の純モジュール**として新規作成
3. [ ] 幾何ヘルパ：凸×凸交差（Sutherland–Hodgman）＋多角形面積（shoelace）
4. [ ] しきい値 `ε`・broad-phase姿勢許容を config 定数化
5. [ ] 着地ロック時（`hamari_game.dart` の update内、`piece.controllable=false` の箇所）に
       隣接ペアを集めて resolver を呼ぶ → 成立で両ピースをフェード除去・加点
6. [ ] ユニットテスト：完全一致／ε境界のズレ／過(はみ出し)／不足(隙間)／非対応姿勢 の5系統で ε スイープ
7. [ ] 既存の tab/notch 形状にコネクタ付与 → 実機で ε を調整（**ここが体験の生命線。時間をかける**）

### 判定の式（ADRより）
- tab と pocket をワールド座標へ写像
- `seated = area(tab ∩ pocket)`
- `fitError = (area(tab) − seated) + (area(pocket) − seated)`  ← 第1項=過、第2項=不足
- `fitError / area(pocket) < ε` で成立

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

`ε`（噛み合い許容）は match_resolver 実装時に追加する。

---

## 5. 設計メモ・前提
- ピースは **凸fixtureの合成**で凹を表現（Box2Dは凹fixture不可）。notch=3分割、形状定義は `piece.dart`。
- 入力は flame の **モダンなイベント系**（TapCallbacks/DragCallbacks）。旧 `TapDetector`/`PanDetector` は非推奨なので使わない。
- 状態管理: 画面跨ぎ（ハイスコア・設定・現在スコア）のみ riverpod、ゲーム内物理状態は Flame 側。混ぜない（spec方針）。
- スコープ判断: MVPは「落として・噛み合わせて・消す」一本。連鎖/色マッチ/日替わりお題は v1 に温存。
