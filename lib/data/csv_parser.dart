import 'package:csv/csv.dart';
import 'package:kindle_reader/utils/logger.dart';

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
  List<Book> _parseToList(List<List<dynamic>> csvData) {
    final List<Book> books = [];
    if (csvData.isEmpty) {
      printWithTimestamp('CSVデータが空です。');
      return books;
    }

    final headers = csvData.first.map((e) => e.toString().toLowerCase().trim()).toList();
    if (csvData.length <= 1) {
      printWithTimestamp('CSVデータにヘッダー行以降のデータがありません。');
      return books;
    }
    for (var i = 1; i < csvData.length; i++) {
      final rowData = csvData[i];
      if (rowData.length < headers.length) {
        printWithTimestamp('行 ${i + 1}: カラム数が不足しています。スキップします。データ: $rowData');
        continue;
      }
      final Map<String, String> row = {};
      for (var j = 0; j < headers.length; j++) {
        row[headers[j]] = rowData[j]?.toString().trim() ?? '';
      }
      final String title = row['title'] ?? '';
      final String authors = row['authors'] ?? '';
      final String purchaseDate = row['date'] ?? '';
      final String status = row['status'] ?? '';
      if (title.isEmpty || authors.isEmpty || purchaseDate.isEmpty || status.isEmpty) {
        printWithTimestamp('行 ${i + 1}: 必須フィールドが空です。スキップします。データ: $row');
        continue;
      }
      books.add(Book(
        id: null,
        title: title,
        authors: authors,
        purchaseDate: purchaseDate,
        status: status,
        genre: null,
        keywords: null,
        coverImagePath: null,
      ));
    }
    return books;
  }

  Future<List<Book>> parseBooksFromCsvString(String csvString) async {
    // _parseToList は同期的だが、将来的に非同期処理が入る可能性も考慮しFutureでラップ
    // または _parseToList を Future<List<Book>> にしてもよい
    return _parseToList(const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(csvString)); 
  }
} 