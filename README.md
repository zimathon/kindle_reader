# Kindle Reader

Kindle書籍管理・分析アプリ（Flutter製）

## 概要

Kindle書籍のCSVデータを読み込み、ジャンル・キーワードの自動付与やカバー画像の自動取得、フィルタ・検索、ステータス管理などを行う多機能な書籍管理アプリです。

- 書籍CSVのインポート（assets/kindle.csv または手動選択）
- SQLiteによるローカルDB管理
- Riverpodによる状態管理
- Gemini API（Google Generative AI）でジャンル・キーワード自動生成
- Google Custom Search APIでカバー画像自動取得
- 書籍リストのフィルタ（ジャンル・ステータス・タイトル・購入日）
- ステータス（未読/読了）切替
- カバー画像の手動/自動設定
- APIキー・検索エンジンIDのSecure Storage管理
- 一括処理・途中停止対応

## ディレクトリ構成

```
kindle_reader/
├── lib/
│   ├── data/                # データモデル・DB・CSVパーサ
│   ├── screens/             # 画面UI（設定画面など）
│   ├── services/            # API/画像検索/セキュアストレージ
│   ├── utils/               # ログ出力などユーティリティ
│   ├── main.dart            # エントリポイント・画面遷移
│   └── providers.dart       # Riverpodプロバイダ・ビジネスロジック
├── assets/
│   └── kindle.csv           # サンプルCSV
├── android/ios/macos/web/   # 各プラットフォーム用
├── pubspec.yaml             # 依存パッケージ
└── README.md
```

## セットアップ

1. 必要なパッケージをインストール

```sh
flutter pub get
```

2. 実行

```sh
flutter run
```

3. 必要に応じて `assets/kindle.csv` を編集・差し替え

4. APIキー（Gemini/Google Search）・検索エンジンIDはアプリの「設定」画面から入力・保存

## 主な依存パッケージ

- [flutter_riverpod](https://pub.dev/packages/flutter_riverpod)（状態管理）
- [dio](https://pub.dev/packages/dio)（HTTP通信）
- [sqflite](https://pub.dev/packages/sqflite)（SQLite DB）
- [csv](https://pub.dev/packages/csv)（CSVパース）
- [file_picker](https://pub.dev/packages/file_picker)（ファイル選択）
- [path_provider](https://pub.dev/packages/path_provider)（パス取得）
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)（APIキー保存）
- [google_generative_ai](https://pub.dev/packages/google_generative_ai)（Gemini API）

## 主な機能

- 書籍CSVのインポート（assetsまたは手動）
- DBへの一括保存・重複チェック
- 書籍リストのフィルタ（ジャンル・ステータス・タイトル・購入日）
- ジャンル・キーワードの自動生成（Gemini API）
- カバー画像の自動取得（Google Custom Search API）
- ステータス（未読/読了）切替
- カバー画像の手動/自動設定
- APIキー・検索エンジンIDのSecure Storage管理
- 一括処理（画像のみ/ジャンルのみ/両方）・途中停止

## 開発Tips

- 状態管理はRiverpod（`lib/providers.dart`）
- DB操作・CSVパースは`lib/data/`配下
- ビジネスロジックは`KindleDataNotifier`（`providers.dart`）
- UIは`lib/main.dart`（一覧・フィルタ）と`lib/screens/settings_screen.dart`（設定）
- 画像取得やLLM処理は非同期・キャンセル対応
- Webビルドは一部機能（画像処理等）が未対応の場合あり

## 注意事項

- Google APIキー・検索エンジンIDはご自身で取得してください
- Gemini API/Google Search APIの利用には利用規約・料金等にご注意ください
- 大量データの一括処理は端末性能・API制限にご注意ください

## ライセンス

MIT License
