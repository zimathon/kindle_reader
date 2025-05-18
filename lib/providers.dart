import 'package:flutter_dotenv/flutter_dotenv.dart'; // flutter_dotenv をインポート
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/csv_parser.dart';
import 'data/database_helper.dart';
import 'services/llm_service.dart';

// 書籍リストの状態を管理するProvider
final bookListProvider = StateNotifierProvider<BookListNotifier, List<Book>>((ref) {
  return BookListNotifier(ref.watch(databaseHelperProvider));
});

class BookListNotifier extends StateNotifier<List<Book>> {
  final DatabaseHelper _dbHelper;
  BookListNotifier(this._dbHelper) : super([]);

  Future<void> loadBooks() async {
    state = await _dbHelper.getAllBooks();
  }

  Future<void> clearBooks() async {
    await _dbHelper.deleteAllBooks(); // DBから全件削除
    state = []; // 状態もクリア
    // ignore: avoid_print
    print('書籍データをクリアし、DBからも全件削除しました。');
  }
}

// DatabaseHelperのインスタンスを提供するProvider
final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper.instance; // シングルトンインスタンスを使用
});

// CsvParserのインスタンスを提供するProvider
final csvParserProvider = Provider<CsvParser>((ref) => CsvParser());

// Gemini APIキーを提供するProvider
final geminiApiKeyProvider = Provider<String?>((ref) {
  return dotenv.env['GEMINI_API_KEY'];
});

// LlmServiceのインスタンスを提供するProvider
final llmServiceProvider = Provider<LlmService>((ref) {
  final apiKey = ref.watch(geminiApiKeyProvider);
  if (apiKey == null || apiKey.isEmpty) {
    // ignore: avoid_print
    print('APIキーが.envファイルに設定されていません。');
    // APIキーがない場合、LlmService内でモデルが初期化されない。
    // エラーをスローするか、ダミーのLlmServiceを返すかなどの対応が必要だが、
    // ここではLlmServiceのコンストラクタにnullを渡し、LlmService側で対応させる。
  }
  return LlmService(apiKey: apiKey); 
});

// データ処理ロジックを担当するProvider (例: KindleDataNotifier)
final kindleDataProvider = Provider<KindleDataNotifier>((ref) {
  return KindleDataNotifier(
    ref.watch(csvParserProvider),
    ref.watch(databaseHelperProvider),
    ref.watch(bookListProvider.notifier),
    ref.watch(llmServiceProvider),
  );
});

class KindleDataNotifier {
  final CsvParser _csvParser;
  final DatabaseHelper _dbHelper;
  final BookListNotifier _bookListNotifier;
  final LlmService _llmService;

  KindleDataNotifier(
    this._csvParser, 
    this._dbHelper, 
    this._bookListNotifier, 
    this._llmService
  );

  Future<String> loadCsvAndSaveToDb() async {
    try {
      // 1. CSVから書籍データを読み込む
      final List<Book> booksFromCsv = await _csvParser.parseBooksFromCsvAsset('assets/kindle.csv');
      if (booksFromCsv.isEmpty) {
        return 'CSVから書籍データを読み込めませんでした。';
      }
      // ignore: avoid_print
      print('CSVから ${booksFromCsv.length} 件の書籍を読み込みました。');

      // 2. データベースに一括挿入 (重複チェックはDatabaseHelper側で今後実装)
      await _dbHelper.batchInsertBooks(booksFromCsv);
      // ignore: avoid_print
      // print('${booksFromCsv.length} 件の書籍をデータベースに保存しました。'); // batchInsertBooks内でログ出力するよう変更したためコメントアウト

      // 3. 書籍リストを更新してUIに反映
      await _bookListNotifier.loadBooks();
      return 'CSVから書籍を読み込み、データベースに保存しました。DB内の書籍数: ${_bookListNotifier.state.length}';
    } catch (e) {
      // ignore: avoid_print
      print('CSV処理またはDB保存中にエラー: $e');
      return 'エラーが発生しました: $e';
    }
  }

  Future<String> processBooksWithLlm({Function(String progress)? onProgress}) async {
    try {
      final allBooks = await _dbHelper.getAllBooks();
      if (allBooks.isEmpty) {
        return 'データベースに書籍がありません。先にCSVから読み込んでください。';
      }

      int processedCount = 0;
      int updatedCount = 0;
      final totalBooksToProcess = allBooks.where((book) => book.id !=null && (book.genre == null || book.genre!.isEmpty)).length;
      
      if (totalBooksToProcess == 0) {
        return 'LLMで処理する対象の書籍(ジャンル未設定)がありませんでした。';
      }
      onProgress?.call('LLM一括処理開始: 対象 $totalBooksToProcess 件');

      for (var book in allBooks) {
        // ジャンルがまだ設定されていない書籍のみ処理
        if (book.id != null && (book.genre == null || book.genre!.isEmpty)) {
          processedCount++;
          // onProgress?.call('一括処理中 ($processedCount/$totalBooksToProcess): ${book.title}'); // 詳細な進捗は任意
          print('LLM一括処理中 ($processedCount/$totalBooksToProcess): ${book.title}');
          try {
            final llmInfo = await _llmService.fetchBookInfoFromLlm(book.title);
            await _dbHelper.updateBookLlmInfo(book.id!, llmInfo['genre']!, llmInfo['keywords']!);
            updatedCount++;
            // ignore: avoid_print
            print('書籍「${book.title}」のLLM情報を更新しました: ジャンル=${llmInfo['genre']}');
          } catch (e, s) { // スタックトレースも受け取る
            // ignore: avoid_print
            print('書籍「${book.title}」のLLM処理中にエラー: $e');
            // onProgress?.call('一括エラー: ${book.title} - $e'); // UIへのエラー詳細表示をコメントアウト
            print('スタックトレース: $s'); // スタックトレースをコンソールに出力
            // エラーが発生しても処理を続行
          }
        }
      }
      await _bookListNotifier.loadBooks(); // UIを更新
      final message = '$updatedCount 件の書籍情報をLLMで更新しました。処理対象は $totalBooksToProcess 件でした。';
      onProgress?.call(message); // 最終結果はUIに表示
      return message;
    } catch (e, s) { // スタックトレースも受け取る
      // ignore: avoid_print
      print('LLM一括処理中にエラー: $e');
      print('スタックトレース: $s'); // スタックトレースをコンソールに出力
      // onProgress?.call('LLM一括処理中にエラーが発生しました: $e'); // UIへのエラー詳細表示をコメントアウト
      return 'LLM一括処理中にエラーが発生しました。'; // UIには簡潔なエラーメッセージを返す
    }
  }

  Future<String> processSingleBookWithLlm(Book book, {Function(String progress)? onProgress}) async {
    if (book.id == null) {
      return 'エラー: 書籍IDがありません。';
    }
    // onProgress?.call('LLM処理開始: ${book.title}'); // UIへの表示は任意
    print('LLM個別処理開始: ${book.title}');
    try {
      final llmInfo = await _llmService.fetchBookInfoFromLlm(book.title);
      await _dbHelper.updateBookLlmInfo(book.id!, llmInfo['genre']!, llmInfo['keywords']!);
      await _bookListNotifier.loadBooks(); // UIを更新
      final message = '書籍「${book.title}」の情報をLLMで更新しました。';
      onProgress?.call(message); // 成功メッセージはUIに表示
      return message;
    } catch (e, s) { // スタックトレースも受け取る
      // ignore: avoid_print
      print('書籍「${book.title}」のLLM処理(個別)中にエラー: $e');
      print('スタックトレース: $s'); // スタックトレースをコンソールに出力
      // onProgress?.call('個別エラー: ${book.title} - $e'); // UIへのエラー詳細表示をコメントアウト
      return '書籍「${book.title}」のLLM処理中にエラーが発生しました。'; // UIには簡潔なエラーメッセージを返す
    }
  }
} 