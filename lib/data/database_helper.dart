import 'package:kindle_reader/utils/logger.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// import 'book_model.dart'; // Bookクラスを別ファイルに移動した場合を想定 (後で調整)
// もし Book モデルが csv_parser.dart にあるならそちらをインポート
import 'csv_parser.dart'; // Bookクラスが定義されているファイルを正しくインポート

class DatabaseHelper {
  static const _databaseName = "KindleReader.db";
  static const _databaseVersion = 1;

  static const tableBooks = 'books';

  static const columnId = 'id';
  static const columnTitle = 'title';
  static const columnAuthors = 'authors';
  static const columnPurchaseDate = 'purchase_date';
  static const columnStatus = 'status';
  static const columnGenre = 'genre';
  static const columnKeywords = 'keywords';
  static const columnCoverImagePath = 'cover_image_path';

  // シングルトンクラスにする
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  // Databaseオブジェクトは一つだけ持つ
  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // データベースを開き、なければ作成する
  _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate);
  }

  // DB作成時にテーブルも作成
  Future _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE $tableBooks (
            $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
            $columnTitle TEXT NOT NULL,
            $columnAuthors TEXT NOT NULL,
            $columnPurchaseDate TEXT NOT NULL,
            $columnStatus TEXT NOT NULL,
            $columnGenre TEXT,
            $columnKeywords TEXT,
            $columnCoverImagePath TEXT
          )
          ''');
  }

  // 挿入 (Create)
  Future<int> insertBook(Book book) async {
    Database db = await instance.database;
    // SQLiteでは、主キーがauto incrementの場合、insert時にはidを指定しないかnullにする
    // Book.toMap()でidがnullの場合は含めないようにしているので、そのまま使える
    return await db.insert(tableBooks, book.toMap());
  }

  // 全件取得 (Read)
  Future<List<Book>> getAllBooks() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(tableBooks);

    if (maps.isEmpty) {
      return [];
    }

    return List.generate(maps.length, (i) {
      return Book.fromMap(maps[i]);
    });
  }

  // 一括挿入 (書籍名で重複チェックを行う)
  Future<int> batchInsertBooks(List<Book> books) async {
    Database db = await instance.database;
    Batch batch = db.batch();
    int newBooksCount = 0;
    int skippedBooksCount = 0;

    for (var book in books) {
      // 既に存在する書籍かどうかをタイトルでチェック
      List<Map<String, dynamic>> existingBooks = await db.query(
        tableBooks,
        columns: [columnId], // 存在確認だけなのでIDのみ取得で十分
        where: '$columnTitle = ?',
        whereArgs: [book.title],
        limit: 1, // 1件見つかれば十分
      );

      if (existingBooks.isEmpty) {
        // 重複がなければ挿入
        batch.insert(tableBooks, book.toMap());
        newBooksCount++;
      } else {
        // ignore: avoid_print
        // print('書籍「${book.title}」は既にデータベースに存在するためスキップしました。');
        skippedBooksCount++;
      }
    }
    await batch.commit(noResult: true);
    // ignore: avoid_print
    printWithTimestamp('$newBooksCount 件の新しい書籍をデータベースに保存しました。$skippedBooksCount 件の書籍は既に存在したためスキップしました。');
    return newBooksCount;
  }

  // 書籍のLLM情報を更新
  Future<int> updateBookLlmInfo(int bookId, String genre, String keywords) async {
    Database db = await instance.database;
    return await db.update(
      tableBooks,
      {
        columnGenre: genre,
        columnKeywords: keywords,
        // TODO: 将来的にカバー画像のパスも更新できるようにするならここに追加
        // columnCoverImagePath: coverImagePath,
      },
      where: '$columnId = ?',
      whereArgs: [bookId],
    );
  }

  // TODO: 必要に応じて以下のメソッドを実装
  // Future<Book?> getBookById(int id) async { ... }
  // Future<int> updateBook(Book book) async { ... }
  // Future<int> deleteBook(int id) async { ... }
  
  // 書籍のステータスを更新
  Future<int> updateBookStatus(int bookId, String newStatus) async {
    Database db = await instance.database;
    return await db.update(
      tableBooks,
      {columnStatus: newStatus},
      where: '$columnId = ?',
      whereArgs: [bookId],
    );
  }

  // 書籍のカバー画像パスを更新
  Future<int> updateBookCoverImage(int bookId, String imagePath) async {
    Database db = await instance.database;
    return await db.update(
      tableBooks,
      {columnCoverImagePath: imagePath},
      where: '$columnId = ?',
      whereArgs: [bookId],
    );
  }

  // 全書籍削除 (デバッグ用など)
  Future<void> deleteAllBooks() async {
    final db = await database;
    await db.delete(tableBooks);
    // ignore: avoid_print
    printWithTimestamp('データベース内の全書籍を削除しました。');
  }

  // ユニークなジャンルリストを取得
  Future<List<String>> getUniqueGenres() async {
    Database db = await instance.database;
    // まず、NULLや空文字でないジャンルを持つ全ての書籍のジャンル文字列を取得
    final List<Map<String, dynamic>> maps = await db.query(
      tableBooks,
      columns: [columnGenre],
      where: '$columnGenre IS NOT NULL AND $columnGenre != ?',
      whereArgs: [''],
    );

    if (maps.isEmpty) {
      return [];
    }

    // 全てのジャンル文字列を収集し、句読点で分割し、フラットなリストにする
    final Set<String> uniqueGenresSet = {}; // 重複排除のためにSetを使用

    for (final map in maps) {
      final String? genreString = map[columnGenre] as String?;
      if (genreString != null && genreString.trim().isNotEmpty) {
        genreString
            .split(RegExp(r'[、,]')) // 読点またはカンマで分割
            .map((g) => g.trim())    // 各要素をトリム
            .where((g) => g.isNotEmpty) // 空の要素を除外
            .forEach((g) => uniqueGenresSet.add(g)); // Setに追加して重複を自動的に排除
      }
    }
    
    // Setをリストに変換し、ソートして返す
    final List<String> sortedGenres = uniqueGenresSet.toList();
    sortedGenres.sort(); // アルファベット順/辞書順にソート

    return sortedGenres;
  }

  // ユニークなステータスリストを取得
  Future<List<String>> getUniqueStatuses() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableBooks,
      distinct: true,
      columns: [columnStatus],
      where: '$columnStatus IS NOT NULL AND $columnStatus != ?',
      whereArgs: [''], // 空文字のステータスを除外
      orderBy: columnStatus,
    );
    return List.generate(maps.length, (i) => maps[i][columnStatus] as String);
  }
} 