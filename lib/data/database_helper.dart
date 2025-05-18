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
  Future<void> batchInsertBooks(List<Book> books) async {
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
    print('$newBooksCount 件の新しい書籍をデータベースに保存しました。$skippedBooksCount 件の書籍は既に存在したためスキップしました。');
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
  
  // 全書籍削除 (デバッグ用など)
  Future<void> deleteAllBooks() async {
    Database db = await instance.database;
    await db.delete(tableBooks);
    // ignore: avoid_print
    print('データベース内の全書籍を削除しました。');
  }
} 