# ADR-001: 噛み合い判定（match_resolver）のアルゴリズム

**Status:** Proposed
**Date:** 2026-06-14
**Deciders:** tatsuya

## Context

落下したピースが静止した瞬間、隣接ピースと「輪郭が過不足なく一致」したかを判定し、成立なら両者を静かに消す。これがアプリ独自価値の中核。設計上の制約と力学：

- **「過不足なく」を1つの調整可能なしきい値で表現したい** — 緩すぎ＝単調、厳しすぎ＝ストレス。この閾値こそ生命線。
- **物理から切り離してテスト可能に**（spec明記）。forge2dの接触に判定を依存させたくない。
- **トリガは静止時のみ** → narrow-phaseは毎フレームではなく着地イベント時だけ走る＝計算予算に余裕。
- 回転は **30°スナップ** ＝相対姿勢が離散。候補絞り込みが容易。
- MVPは **形のみ・ペア消し**。v1で色マッチ／多ピース同時を足せる余地を残す。

## Decision

**ハイブリッド：コネクタ・メタデータ（broad-phase）＋ 凸ポリゴンの面積フィット誤差（narrow-phase）を、単一しきい値 ε に対して判定する純関数。**

各 `PieceShape` の凸/凹に「コネクタ」を持たせる：

- **tab** = 凸の出っ張りポリゴン（凸）
- **pocket** = 凹の空き領域ポリゴン（凸）＝ネガティブスペース

判定（着地時、対象ピースと隣接ピース各ペアについて）：

1. **broad-phase**：互いのコネクタが向き合い、30°スナップ上で相補的な姿勢か（離散チェック）。違えば即棄却。
2. **narrow-phase**：tab と pocket をワールド座標へ写し、**凸×凸の交差**（Sutherland–Hodgman）で `seated = area(tab ∩ pocket)` を計算。
   - `fitError = (area(tab) − seated) + (area(pocket) − seated)`
     - 第1項 = **過**（pocketからはみ出たtab）
     - 第2項 = **不足**（埋まらなかったpocketの隙間）
   - `fitError / area(pocket) < ε` なら成立 → 両者フェード消滅・加点。

`ε`（相対面積誤差）が「どれだけぴたりなら成立か」そのもの。唯一の調整ノブ。

## Options Considered

### Option A: 凸ポリゴンの面積フィット誤差（採用の中核）

| Dimension | Assessment |
|-----------|------------|
| Complexity | Med（凸×凸交差のみ。一般のconcave booleanは不要） |
| Cost | Low（着地時のみ・対象は隣接数ペア） |
| Scalability | High（色/多ピースへ拡張容易） |
| Team familiarity | High（純粋な幾何・テスト容易） |

**Pros:** 「過/不足」を面積として直接測れる。閾値が物理的に意味を持ち1個で済む。物理非依存で完全にユニットテスト可能。
**Cons:** コネクタ・メタデータの authoring が要る。凸分解前提（既存のfixture設計と整合）。

### Option B: コネクタ・タグのみで一致（broad-phaseだけで確定）

| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | Very Low |
| Scalability | Med |
| Team familiarity | High |

**Pros:** 最速・決定的。30°離散と相性最高。
**Cons:** 「ぴたり度」を姿勢許容だけで表現＝面積的な過不足を測れず、**スクリプト的で「収まった」手触りが出にくい**。閾値の説得力が弱い。→ 単独不採用、broad-phaseとして A に内包。

### Option C: 占有グリッド（ラスタライズ＋flood fill）

| Dimension | Assessment |
|-----------|------------|
| Complexity | Med-High |
| Cost | Med |
| Scalability | High（多ピースの「穴埋め」が自然） |
| Team familiarity | Med |

**Pros:** 複数ピースが集合的に隙間を埋めるケースを自然に検出。
**Cons:** 30°でのエイリアシング、セル解像度＝精度のトレードオフ、「過不足なく」がセル粒度で粗い。MVPには重い。→ **v1の多ピース対応で再検討**。

### Option D: forge2dの接触マニフォルド（却下）

**Pros:** 安価、specの「接触イベント起点」に沿う。
**Cons:** polygon-polygonの接触点は≤2点に切られ、輪郭全体の一致を測れない。判定が物理に密結合し、**テスト容易性というspec要件に反する**。→ 却下。

## Trade-off Analysis

核心は「**閾値の意味づけ**」と「**テスト容易性**」。Aは過不足を面積という単一の物理量に落とすため、`ε` を触るだけで体験を調律でき、その `ε` スイープを物理なしで自動テストできる（生命線の調整ループが速い）。Bは速いが「ぴたり」の質感を持てない＝中核価値を毀損。Cは将来の多ピースには最適だがMVPには過剰。Dはspecのテスト容易性要件と衝突。
→ **A（narrow）＋ Bをbroad-phaseに格下げ内包**が、質感・調整性・テスト性・拡張性を同時に満たす。

## Consequences

- **易化**：`ε` 一発で体験チューニング。判定が `Iterable<Vector2>` を入出力する純関数になり、forge2d不要でテスト可能。色マッチ（v1）は narrow-phase に色一致条件を AND するだけ。
- **難化**：各 `PieceShape` に tab/pocket コネクタ・メタデータを author する責務が増える（形状定義と二重管理に注意）。凸前提を崩す形（曲線等）は将来別途。
- **再訪が必要**：多ピース同時嵌め／連鎖（v1）は A では表現しづらい → その時に **Option C（占有グリッド）** をnarrow-phaseに併設して評価する。

## Action Items

1. [ ] `PieceShape` に `connectors: List<Connector>`（type=tab/pocket, polygon, 基準法線/向き）を追加
2. [ ] `systems/match_resolver.dart` を純モジュールとして実装（forge2d非依存）
3. [ ] 幾何ヘルパ：凸×凸交差（Sutherland–Hodgman）＋多角形面積（shoelace）
4. [ ] `ε`（既定値）と broad-phase姿勢許容を `config` 定数化
5. [ ] 着地ロック時に隣接ペアを集めて resolver 呼び出し → 成立で両ピースをフェード除去・加点
6. [ ] ユニットテスト：完全一致／僅かなズレ（ε境界）／過（はみ出し）／不足（隙間）／非対応姿勢、の5系統で `ε` スイープ
7. [ ] 既存の `piece.dart` 形状（tab/notch）にコネクタを付与し、手触りを実機で `ε` 調整
