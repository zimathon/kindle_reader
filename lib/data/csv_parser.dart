import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;

// 仮の書籍データモデル (design.md に合わせて後で詳細化)
class Book {
  final int? id; // SQLiteで自動インクリメント
  final String title;
  final String authors;
  final String purchaseDate; // CSVからは "YYYY年M月D日" 形式の文字列として読み込む
  final String status;
  final String? genre; // LLMによる付加情報
  final String? keywords; // LLMによる付加情報
  final String? coverImagePath; // オプションのカバー画像パス

  Book({
    this.id,
    required this.title,
    required this.authors,
    required this.purchaseDate,
    required this.status,
    this.genre,
    this.keywords,
    this.coverImagePath,
  });

  Book copyWith({
    int? id,
    String? title,
    String? authors,
    String? purchaseDate,
    String? status,
    String? genre,
    String? keywords,
    String? coverImagePath,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      status: status ?? this.status,
      genre: genre ?? this.genre,
      keywords: keywords ?? this.keywords,
      coverImagePath: coverImagePath ?? this.coverImagePath,
    );
  }

  // SQLite保存用のMapに変換 (idがnullの場合は含めない)
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'title': title,
      'authors': authors,
      'purchase_date': purchaseDate, // DBカラム名に合わせる
      'status': status,
      'genre': genre,
      'keywords': keywords,
      'cover_image_path': coverImagePath,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  // MapからBookオブジェクトに変換
  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int?,
      title: map['title'] as String,
      authors: map['authors'] as String,
      purchaseDate: map['purchase_date'] as String, // DBカラム名に合わせる
      status: map['status'] as String,
      genre: map['genre'] as String?,
      keywords: map['keywords'] as String?,
      coverImagePath: map['cover_image_path'] as String?,
    );
  }

  // デバッグやログ出力用にtoStringをオーバーライド (任意)
  @override
  String toString() {
    return 'Book{id: $id, title: $title, authors: $authors, purchaseDate: $purchaseDate, status: $status, genre: $genre, keywords: $keywords, coverImagePath: $coverImagePath}';
  }

  // TODO: design.md のテーブル設計に合わせて、toMap() や fromMap() メソッドを
  //       後で追加する (SQFliteで利用するため)
}

class CsvParser {
  Future<List<Book>> parseBooksFromCsvAsset(String assetPath) async {
    final List<Book> books = [];
    try {
      final rawCsvData = await rootBundle.loadString(assetPath);
      // CSVパーサーの設定: Windows/Mac/Linuxの改行コードの違いに対応しやすくするため eol を指定
      final List<List<dynamic>> listData =
          const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
              .convert(rawCsvData);

      if (listData.isEmpty) {
        // ignore: avoid_print
        print('CSVデータが空です。');
        return books;
      }

      // ヘッダー行をスキップするため、データは1行目から処理 (ユーザー指示)
      // CSVファイルにヘッダー行しかデータがない場合も考慮
      if (listData.length < 2) {
        // ignore: avoid_print
        print('CSVデータにヘッダー行以降のデータがありません。');
        return books;
      }

      // ヘッダー行のログ出力 (デバッグ用)
      // final headerRow = listData.first;
      // print('CSV Header: $headerRow');

      for (var i = 1; i < listData.length; i++) {
        final row = listData[i];

        // カラム数のチェック (必須フィールドは4つ)
        if (row.length < 4) {
          // ignore: avoid_print
          print('行 ${i + 1}: カラム数が不足しています（期待値4以上、実際は${row.length}）。スキップします。データ: $row');
          continue;
        }

        // 各フィールドの値を安全に取得し、前後の空白を除去
        // rowの各要素がnullの可能性も考慮し、?? '' で空文字をデフォルト値とする
        final String title = row[0]?.toString().trim() ?? '';
        final String authors = row[1]?.toString().trim() ?? '';
        final String purchaseDate = row[2]?.toString().trim() ?? '';
        final String status = row[3]?.toString().trim() ?? '';

        // 必須フィールドの空チェック
        if (title.isEmpty ||
            authors.isEmpty ||
            purchaseDate.isEmpty ||
            status.isEmpty) {
          // ignore: avoid_print
          print('行 ${i + 1}: 必須フィールドが空です。スキップします。データ: $row');
          continue;
        }

        books.add(Book(
          title: title,
          authors: authors,
          purchaseDate: purchaseDate, // "YYYY年M月D日" 形式のまま
          status: status,
          id: null, // CSVからはIDを読み込まない
          genre: null, // LLMで後から付与
          keywords: null, // LLMで後から付与
          coverImagePath: null, // LLMで後から付与 (オプション)
        ));
      }
    } catch (e) {
      // ignore: avoid_print
      print('CSVファイルの読み込みまたはパース中にエラーが発生しました: $e');
      // エラー発生時は空のリストを返すか、より詳細なエラー処理を行うかはアプリの要件による
    }
    return books;
  }
} 