# Google Maps Saved Companion App - 使用手順書

## 目次

1. [システム概要](#1-システム概要)
2. [事前準備](#2-事前準備)
3. [Google Cloud プロジェクト設定](#3-google-cloud-プロジェクト設定)
4. [Google Takeout の準備](#4-google-takeout-の準備)
5. [同期の実行](#5-同期の実行)
6. [同期パイプラインの処理フロー](#6-同期パイプラインの処理フロー)
7. [グループ管理](#7-グループ管理)
8. [分類ルール管理](#8-分類ルール管理)
9. [データモデル仕様](#9-データモデル仕様)
10. [エラーコードと対処法](#10-エラーコードと対処法)
11. [キャッシュ管理](#11-キャッシュ管理)
12. [アーキテクチャ構成](#12-アーキテクチャ構成)

---

## 1. システム概要

Google Maps の「保存済みの場所」を Google Takeout 経由で取り込み、ルールベースで自動分類し、SQLite に同期管理するバックエンドエンジンです。

### 主な機能

- Google Drive 上の Takeout アーカイブを自動検出・ダウンロード
- ZIP 展開 → CSV 解析 → 正規化 → 差分同期
- ルールベースの自動分類（1つの場所を複数グループに分類可能）
- 手動グループ割り当ての保護（自動分類で上書きされない）
- 削除候補の安全な管理（物理削除なし、2回連続未検出で非表示化）

### 現在の状態

バックエンド処理のみ実装済み（UI未実装）。将来的にFlutter UIを構築して使用します。

---

## 2. 事前準備

### 必要な環境

| 項目 | バージョン |
|------|-----------|
| Flutter SDK | 3.11.1 以上 |
| Dart SDK | 3.11.1 以上 |
| Xcode | 最新版（iOS ビルド用） |
| Android Studio | 最新版（Android ビルド用） |

### Flutter のインストール確認

```bash
flutter --version
flutter doctor
```

### 依存パッケージのインストール

```bash
cd ~/.claude/tool/maps_saved_app
flutter pub get
```

### テストの実行確認

```bash
flutter test
flutter analyze
```

---

## 3. Google Cloud プロジェクト設定

Takeout アーカイブを Google Drive から取得するため、OAuth 2.0 の設定が必要です。

### 3.1 Google Cloud Console でプロジェクト作成

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 「新しいプロジェクト」を作成
3. プロジェクト名を入力（例: `maps-saved-companion`）

### 3.2 Google Drive API の有効化

1. 「APIとサービス」→「ライブラリ」
2. 「Google Drive API」を検索して有効化

### 3.3 OAuth 同意画面の設定

1. 「APIとサービス」→「OAuth 同意画面」
2. ユーザータイプ: **外部**
3. 必要情報を入力:
   - アプリ名
   - ユーザーサポートメール
   - デベロッパー連絡先
4. スコープに `https://www.googleapis.com/auth/drive.readonly` を追加
5. テストユーザーに自分のGmailアドレスを追加

### 3.4 OAuth クライアント ID の作成

**iOS の場合:**
1. 「認証情報」→「認証情報を作成」→「OAuth クライアント ID」
2. アプリケーションの種類: **iOS**
3. バンドル ID を入力（`ios/Runner.xcodeproj` の Bundle Identifier）
4. 生成された `GoogleService-Info.plist` を `ios/Runner/` に配置

**Android の場合:**
1. アプリケーションの種類: **Android**
2. パッケージ名を入力（`android/app/build.gradle` の applicationId）
3. SHA-1 フィンガープリントを入力:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
   ```
4. 生成された `google-services.json` を `android/app/` に配置

---

## 4. Google Takeout の準備

### 4.1 Takeout データのエクスポート

1. [Google Takeout](https://takeout.google.com/) にアクセス
2. 「選択をすべて解除」をクリック
3. **「マップ（マイプレイス）」** のみにチェック
4. エクスポート設定:
   - 配信方法: **Google ドライブに追加**
   - 頻度: 1回エクスポート（または定期エクスポート）
   - ファイル形式: **.zip**
   - ファイルサイズ: 2GB（デフォルト）
5. 「エクスポートを作成」をクリック

### 4.2 エクスポートの確認

- エクスポート完了後、Google Drive に `takeout-YYYYMMDD-NNN.zip` が保存される
- 大きいデータの場合、分割アーカイブ（001, 002, ...）になる
- アプリはこの分割を自動検出・統合する

### 4.3 Takeout ZIP の中身

```
takeout-20260315-001.zip
└── Takeout/
    └── マップ（マイプレイス）/
        └── 保存済みの場所.csv    ← これが取り込み対象
```

CSV のヘッダー例:
```
Title,Note,URL,Comment
桜の名所 公園,春に行きたい,https://maps.google.com/...,きれいな桜
```

---

## 5. 同期の実行

### 5.1 基本的な同期（コード呼び出し）

```dart
// 各サービスの初期化（DI コンテナまたは手動）
final logger = SyncLogger();
final authService = GoogleAuthService(logger: logger);
final driveService = GoogleDriveService(authService: authService, logger: logger);
final archiveLocator = TakeoutArchiveLocator(driveService: driveService, logger: logger);
final downloader = ArchiveDownloader(driveService: driveService, logger: logger);
final extractor = ArchiveExtractor(logger: logger);
final cacheService = FileCacheService(logger: logger);
final csvDiscovery = CsvDiscoveryService(logger);
final csvParser = CsvParser(logger);
final normalizer = PlaceNormalizer();
final sourceKeyGen = SourceKeyGenerator();
final appDatabase = AppDatabase();
final placeRepo = SqlitePlaceRepository(appDatabase);
final groupRepo = SqliteGroupRepository(appDatabase);
final placeGroupRepo = SqlitePlaceGroupRepository(appDatabase);
final syncJobRepo = SqliteSyncJobRepository(appDatabase);
final ruleRepo = SqliteClassificationRuleRepository(appDatabase);
final classifier = RuleBasedClassificationEngine(ruleRepo, logger);
final classificationOrch = ClassificationOrchestrator(
  classifier, placeRepo, placeGroupRepo, groupRepo, logger,
);
final diffEngine = DiffEngine(placeRepo, sourceKeyGen, logger);
final diffApplier = DiffApplier(placeRepo, sourceKeyGen, logger);

// SyncOrchestrator の構築
final orchestrator = SyncOrchestrator(
  authService: authService,
  archiveLocator: archiveLocator,
  downloader: downloader,
  extractor: extractor,
  cacheService: cacheService,
  csvDiscovery: csvDiscovery,
  csvParser: csvParser,
  normalizer: normalizer,
  diffEngine: diffEngine,
  diffApplier: diffApplier,
  classificationOrchestrator: classificationOrch,
  syncJobRepository: syncJobRepo,
  logger: logger,
);

// 同期実行
final summary = await orchestrator.runSync();
print('結果: ${summary.status}');
print('新規: ${summary.newCount}');
print('更新: ${summary.updatedCount}');
print('未変更: ${summary.unchangedCount}');
```

### 5.2 同期オプション

```dart
// 通常同期（前回と同じアーカイブはスキップ）
await orchestrator.runSync();

// 強制同期（同じアーカイブでも再処理）
await orchestrator.runSync(const SyncOptions(forceSync: true));

// 分類のみ再実行（外部データ取得なし）
await orchestrator.runSync(const SyncOptions(rebuildOnly: true));
```

### 5.3 同期結果（SyncSummary）

| フィールド | 説明 |
|-----------|------|
| `status` | `"success"` / `"partial"` / `"failed"` |
| `newCount` | 新規追加された場所の数 |
| `updatedCount` | 更新された場所の数 |
| `unchangedCount` | 変更なしの場所の数 |
| `deletedCandidateCount` | 今回不在だった場所の数 |
| `skippedRowCount` | 解析できずスキップした行の数 |
| `archiveName` | 処理したアーカイブ名 |

---

## 6. 同期パイプラインの処理フロー

```
1. Google 認証
   └─ サイレントサインイン → 失敗時はインタラクティブサインイン

2. アーカイブ検出
   └─ Drive API で "takeout" を含む ZIP を検索
   └─ 分割アーカイブを自動グループ化
   └─ 最新グループを選択

3. 重複チェック
   └─ 前回成功した同期と同じアーカイブなら → スキップ（forceSync=true で回避）

4. ダウンロード
   └─ Drive からローカルキャッシュにダウンロード
   └─ 失敗時は指数バックオフで3回リトライ（1秒→3秒→10秒）

5. ZIP 展開
   └─ Zip Slip 防御（パストラバーサル、絶対パス、隠しファイル排除）
   └─ サイズ上限: 500MB / ファイル数上限: 10,000

6. CSV 検出
   └─ 展開ディレクトリ内の CSV をヘッダー・ファイル名でスコアリング
   └─ スコア 3 以上を候補として採用

7. CSV 解析 → 正規化
   └─ BOM 除去、UTF-8 デコード
   └─ ヘッダー正規化（小文字化、スペース→アンダースコア）
   └─ フィールドマッピング（Title→sourceTitle, URL→mapsUrl 等）

8. 差分計算（Diff）
   └─ source_key（URL の SHA-256 ハッシュ）で既存レコードと照合
   └─ 新規 / 更新 / 未変更 / 不在 に分類

9. DB 適用
   └─ 新規 → INSERT
   └─ 更新 → UPDATE（lastSeenAt 更新、削除フラグリセット）
   └─ 未変更 → lastSeenAt のみ更新
   └─ 不在 → deletedMissCount+1、2回連続で isHidden=true

10. 自動分類
    └─ 有効な分類ルールで各場所を評価
    └─ マッチしたグループに割り当て（複数可）
    └─ マッチなし → 「未分類」グループに割り当て
    └─ 手動オーバーライド済みの場所はスキップ
    └─ 分類失敗は非致命的（status="partial"、データ同期は完了）

11. ジョブ記録
    └─ sync_jobs テーブルに結果を記録

12. キャッシュクリーンアップ
    └─ 当該ジョブの展開ファイル削除
    └─ ダウンロードしたアーカイブ削除
    └─ 24時間以上古いキャッシュを自動削除
```

---

## 7. グループ管理

### 7.1 初期グループ（シードデータ）

| グループ名 | アイコン | 用途 |
|-----------|---------|------|
| 春 | flower | 春の撮影スポット |
| 夏 | sunny | 夏の撮影スポット |
| 秋 | leaf | 秋の撮影スポット |
| 冬 | snow | 冬の撮影スポット |
| 桜スポット | cherry_blossom | 桜の名所 |
| 飲食店 | restaurant | 飲食店 |
| 星景 | star | 星景撮影スポット |
| 家族向け | family | 家族で行ける場所 |
| 未分類 | help_outline | どのルールにもマッチしない場所（**システムグループ: 削除不可**）|

### 7.2 グループの操作

```dart
final groupRepo = SqliteGroupRepository(appDatabase);

// 一覧取得
final groups = await groupRepo.listAll();

// グループ追加
await groupRepo.upsert(Group(
  id: Uuid().v4(),
  name: '夜景スポット',
  iconName: 'nightlight',
  colorKey: 'purple',
  sortOrder: 10,
));

// グループ編集
final group = await groupRepo.findById('...');
await groupRepo.upsert(group!.copyWith(name: '夜景・イルミ'));

// グループ削除（システムグループ「未分類」は削除不可）
await groupRepo.delete('group-id');
```

### 7.3 手動グループ割り当て

```dart
final placeGroupRepo = SqlitePlaceGroupRepository(appDatabase);

// 手動割り当て（source: "manual" で登録すると自動分類で上書きされない）
await placeGroupRepo.replaceAutoGroups(placeId, [
  PlaceGroup(
    placeId: placeId,
    groupId: targetGroupId,
    source: 'manual',  // ← これが重要
    confidence: 1.0,
    createdAt: DateTime.now(),
  ),
]);

// 手動オーバーライドフラグを有効化
final place = await placeRepo.findById(placeId);
await placeRepo.update(place!.copyWith(manualGroupOverride: true));
```

`manualGroupOverride = true` の場所は自動分類処理で完全にスキップされます。

---

## 8. 分類ルール管理

### 8.1 初期ルール

| 対象グループ | パターン（`\|` = OR）| 対象フィールド | 優先度 |
|-------------|---------------------|---------------|--------|
| 春 | `桜\|花見\|さくら\|菜の花\|春` | title, note, comments, collectionName | 10 |
| 桜スポット | `桜\|花見\|さくら` | title, note, comments | 10 |
| 飲食店 | `飲食店\|ランチ\|ディナー\|カフェ\|喫茶\|レストラン` | title, note, comments, collectionName | 20 |
| 星景 | `星\|星空\|天の川\|夜景` | title, note, comments | 20 |
| 秋 | `紅葉\|もみじ\|いちょう\|秋` | title, note, comments | 20 |
| 夏 | `海\|花火\|ひまわり\|川\|夏` | title, note, comments | 20 |
| 冬 | `雪\|イルミ\|クリスマス\|温泉\|冬` | title, note, comments | 20 |
| 家族向け | `公園\|遊園地\|動物園\|水族館\|キッズ\|子供\|家族` | title, note, comments, collectionName | 30 |

### 8.2 ルールの動作

- パターン内の `|` は OR 条件（いずれかにマッチすれば該当）
- 対象フィールドの値を結合してパターンマッチ
- 優先度の数値が小さいほど先に評価される
- 1つの場所が複数ルールにマッチした場合、すべてのグループに割り当て
- 同じグループに複数ルールがマッチした場合は、最初にマッチしたルールが採用

### 8.3 ルールの操作

```dart
final ruleRepo = SqliteClassificationRuleRepository(appDatabase);

// ルール一覧
final rules = await ruleRepo.listAll();
final enabledRules = await ruleRepo.listEnabled();

// ルール追加
await ruleRepo.insert(ClassificationRule(
  id: Uuid().v4(),
  groupId: 'target-group-id',
  pattern: '神社|寺|仏閣|お寺',
  targetFields: ['title', 'note', 'comments'],
  isRegex: false,   // true にすると正規表現として解釈
  priority: 20,
  enabled: true,
));

// ルール編集
final rule = rules.first;
await ruleRepo.update(rule.copyWith(pattern: '神社|寺|仏閣|お寺|鳥居'));

// ルール無効化（削除せず一時停止）
await ruleRepo.update(rule.copyWith(enabled: false));

// ルール削除
await ruleRepo.delete(rule.id);

// 分類の再実行（ルール変更後）
await orchestrator.runSync(const SyncOptions(rebuildOnly: true));
```

### 8.4 正規表現ルール

`isRegex: true` にすると、パターンが正規表現として評価されます（大文字小文字無視）。

```dart
// 例: 「〇〇温泉」「温泉〇〇」のようなパターンをマッチ
ClassificationRule(
  id: Uuid().v4(),
  groupId: winterGroupId,
  pattern: r'.*温泉.*|.*露天.*',
  targetFields: ['title'],
  isRegex: true,
  priority: 15,
  enabled: true,
);
```

不正な正規表現が設定された場合、エラーにはならずマッチしないものとして処理されます（ログに警告が出力）。

---

## 9. データモデル仕様

### 9.1 Place（場所）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `id` | String | UUID（自動生成） |
| `sourceKey` | String | URL の SHA-256 ハッシュ（重複検出用） |
| `sourceTitle` | String? | 場所の名前 |
| `mapsUrl` | String? | Google Maps URL |
| `note` | String? | メモ |
| `comments` | String? | コメント |
| `collectionName` | String? | コレクション名 |
| `collectionDescription` | String? | コレクション説明 |
| `createdAt` | DateTime | 初回取り込み日時 |
| `updatedAt` | DateTime | 最終更新日時 |
| `lastSeenAt` | DateTime | 最後にアーカイブで確認された日時 |
| `isHidden` | bool | 非表示フラグ（2回連続不在で true） |
| `isDeletedCandidate` | bool | 削除候補フラグ |
| `deletedMissCount` | int | 連続不在カウント |
| `manualGroupOverride` | bool | 手動グループ割り当て保護フラグ |

### 9.2 削除ロジック

物理削除は行いません。代わりに以下の安全な仕組みを使います:

```
1回目の不在: isDeletedCandidate=true, deletedMissCount=1
2回目の不在: isHidden=true, deletedMissCount=2 → リスト非表示
再出現時:    すべてのフラグがリセットされ、再びアクティブに
```

---

## 10. エラーコードと対処法

| エラーコード | 意味 | 対処法 |
|-------------|------|--------|
| `authRequired` | Google サインインが必要 | アプリ内でサインインを実行 |
| `tokenExpired` | アクセストークンの期限切れ | 再認証が必要（通常は自動リフレッシュ） |
| `archiveNotFound` | Drive 上に Takeout アーカイブが見つからない | Google Takeout でエクスポートを実行（配信先: Google Drive） |
| `downloadFailed` | アーカイブのダウンロードに失敗 | ネットワーク接続を確認。3回リトライ後に発生 |
| `zipExtractFailed` | ZIP の展開に失敗 | ファイルの破損、サイズ超過（500MB）、ファイル数超過（10,000）|
| `csvNotFound` | アーカイブ内に対象 CSV が見つからない | Takeout で「マップ（マイプレイス）」を選択してエクスポート |
| `csvParseFailed` | CSV の解析に失敗 | CSV フォーマットが想定外。ログで詳細確認 |
| `dbWriteFailed` | データベース書き込みエラー | ストレージ容量の確認、アプリ再起動 |

### 同期ステータス

| ステータス | 意味 |
|-----------|------|
| `success` | 全工程が正常完了 |
| `partial` | データ同期は成功したが分類処理に一部失敗あり |
| `failed` | 同期が失敗（データは前回の状態を維持） |

---

## 11. キャッシュ管理

### 自動管理

同期完了時に以下が自動実行されます:
- 当該ジョブの展開ファイル削除
- ダウンロードしたアーカイブ削除
- 24時間以上古いキャッシュの自動削除

### 手動管理

```dart
final cacheService = FileCacheService(logger: logger);

// キャッシュサイズの確認（バイト単位）
final sizeBytes = await cacheService.getCacheSize();
print('キャッシュサイズ: ${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB');

// 古いキャッシュの手動クリーンアップ（デフォルト: 24時間以上）
final removedCount = await cacheService.cleanupStale();

// カスタム期間で削除（例: 6時間以上古いもの）
final removed = await cacheService.cleanupStale(const Duration(hours: 6));

// 全キャッシュ削除
await cacheService.cleanupAll();
```

---

## 12. アーキテクチャ構成

```
lib/
├── domain/                          # ドメイン層（ビジネスロジック）
│   ├── models/                      # データモデル
│   │   ├── place.dart               # 場所
│   │   ├── group.dart               # グループ
│   │   ├── place_group.dart         # 場所×グループ紐付け
│   │   ├── classification_rule.dart # 分類ルール
│   │   ├── classification_hit.dart  # 分類結果
│   │   ├── sync_job.dart            # 同期ジョブ
│   │   ├── sync_summary.dart        # 同期サマリー
│   │   ├── diff_result.dart         # 差分計算結果
│   │   ├── normalized_place_record.dart  # 正規化済みレコード
│   │   ├── raw_place_record.dart    # 生CSVレコード
│   │   ├── archive_descriptor.dart  # Drive上のアーカイブ情報
│   │   └── app_error.dart           # エラー定義
│   └── repositories/                # リポジトリインターフェース
│       ├── place_repository.dart
│       ├── group_repository.dart
│       ├── place_group_repository.dart
│       ├── classification_rule_repository.dart
│       ├── sync_job_repository.dart
│       └── place_classifier.dart
│
├── infrastructure/                  # インフラ層（実装）
│   ├── auth/
│   │   └── google_auth_service.dart      # Google OAuth 2.0
│   ├── drive/
│   │   ├── google_drive_service.dart     # Drive API 操作
│   │   └── takeout_archive_locator.dart  # アーカイブ検出・グループ化
│   ├── archive/
│   │   ├── archive_downloader.dart       # ダウンロード（リトライ付き）
│   │   ├── archive_extractor.dart        # ZIP展開（セキュリティ防御）
│   │   └── file_cache_service.dart       # キャッシュ管理
│   ├── csv/
│   │   ├── csv_parser.dart               # CSV解析
│   │   ├── csv_discovery_service.dart    # CSV自動検出
│   │   └── place_normalizer.dart         # フィールド正規化
│   ├── sync/
│   │   ├── sync_orchestrator.dart        # 同期パイプライン全体制御
│   │   ├── diff_engine.dart              # 差分計算
│   │   ├── diff_applier.dart             # 差分DB適用
│   │   ├── source_key_generator.dart     # source_key生成（SHA-256）
│   │   └── url_normalizer.dart           # URL正規化
│   ├── classification/
│   │   └── classification_engine.dart    # ルールベース分類 + オーケストレーター
│   ├── database/
│   │   ├── app_database.dart             # SQLiteスキーマ・初期化
│   │   ├── seed_data.dart                # 初期データ投入
│   │   ├── sqlite_place_repository.dart
│   │   ├── sqlite_group_repository.dart
│   │   ├── sqlite_place_group_repository.dart
│   │   ├── sqlite_sync_job_repository.dart
│   │   └── sqlite_classification_rule_repository.dart
│   └── logging/
│       └── sync_logger.dart              # 構造化ログ
│
└── main.dart
```

### 依存パッケージ

| パッケージ | 用途 |
|-----------|------|
| `sqflite` | SQLite データベース |
| `google_sign_in` | Google OAuth 2.0 認証 |
| `flutter_secure_storage` | トークンの安全な保管 |
| `http` | HTTP クライアント |
| `archive` | ZIP 展開 |
| `csv` | CSV 解析 |
| `crypto` | SHA-256 ハッシュ（source_key 生成）|
| `uuid` | UUID 生成 |
| `path_provider` | アプリディレクトリ取得 |

---

## 補足: テスト実行

```bash
# 全テスト実行（195件）
flutter test

# 特定テストファイルのみ実行
flutter test test/sync_logger_test.dart

# 静的解析
flutter analyze
```
