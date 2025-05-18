import 'dart:async'; // 追加
import 'dart:io'; // ファイル操作のため
import 'dart:typed_data'; // Uint8List を使用するため
import 'dart:ui' as ui; // 追加

import 'package:dio/dio.dart'; // dio をインポート
import 'package:file_picker/file_picker.dart'; // ファイルピッカー
import 'package:flutter/material.dart'; // material.dart をインポート
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart'; // 日付フォーマットのため
import 'package:kindle_reader/utils/logger.dart';
import 'package:path/path.dart' as p; // path ライブラリを p としてインポート
import 'package:path_provider/path_provider.dart'; // path_provider をインポート

import 'data/csv_parser.dart';
import 'data/database_helper.dart';
import 'services/image_search_service.dart'; // ImageSearchServiceをインポート
import 'services/llm_service.dart';
import 'services/secure_storage_service.dart'; // SecureStorageService をインポート

// 書籍リストの状態を管理するProvider
final bookListProvider = StateNotifierProvider<BookListNotifier, List<Book>>((ref) {
  return BookListNotifier(ref.watch(databaseHelperProvider), ref);
});

class BookListNotifier extends StateNotifier<List<Book>> {
  final DatabaseHelper _dbHelper;
  final Ref _ref;

  BookListNotifier(this._dbHelper, this._ref) : super([]);

  Future<void> loadBooks() async {
    state = await _dbHelper.getAllBooks();
  }

  Future<void> updateSingleBookInList(Book updatedBook) async {
    state = [
      for (final book in state)
        if (book.id == updatedBook.id) updatedBook else book,
    ];
  }

  Future<void> clearBooks() async {
    await _dbHelper.deleteAllBooks(); // DBから全件削除
    state = []; // 状態もクリア
    printWithTimestamp('書籍データをクリアし、DBからも全件削除しました。');
    _ref.read(processingStatusProvider.notifier).state = '待機中';
  }
}

// DatabaseHelperのインスタンスを提供するProvider
final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper.instance; // シングルトンインスタンスを使用
});

// CsvParserのインスタンスを提供するProvider
final csvParserProvider = Provider<CsvParser>((ref) => CsvParser());

// SecureStorageServiceのインスタンスを提供するProvider
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

// Gemini APIキーを提供するProvider
final geminiApiKeyProvider = FutureProvider<String?>((ref) async {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  String? apiKey = await secureStorage.getGeminiApiKey();
  if (apiKey == null || apiKey.isEmpty) {
    printWithTimestamp('SecureStorageにGemini APIキーが見つかりません。');
    return null; // .envからの読み込みは行わず、nullを返す
  }
  // SecureStorageにキーがあればそれを返す。再保存は不要。
  return apiKey;
});

// LlmServiceのインスタンスを提供するProvider
final llmServiceProvider = Provider<LlmService>((ref) {
  final apiKeyAsyncValue = ref.watch(geminiApiKeyProvider);
  
  return apiKeyAsyncValue.when(
    data: (apiKey) {
      if (apiKey == null || apiKey.isEmpty) {
        printWithTimestamp('LlmServiceプロバイダ: Gemini APIキーが利用できません。');
        // APIキーがない場合でもLlmServiceインスタンスは生成するが、機能は限定される
        return LlmService(apiKey: null);
      }
      return LlmService(apiKey: apiKey);
    },
    loading: () {
      printWithTimestamp('LlmServiceプロバイダ: Gemini APIキーを読み込み中です...');
      // ローディング中はダミーのサービスを返すか、あるいは特定の処理を行う
      return LlmService(apiKey: null); // または例外をスロー、ローディング状態を示す別の方法も
    },
    error: (error, stackTrace) {
      printWithTimestamp('LlmServiceプロバイダ: Gemini APIキーの読み込み中にエラー: $error');
      return LlmService(apiKey: null); // エラー時も同様
    },
  );
});

// Google Programmable Search APIキーを提供するProvider
final googleSearchApiKeyProvider = FutureProvider<String?>((ref) async {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  // SecureStorageServiceの修正により、getGoogleSearchApiKeyは実質Geminiキーを読む
  String? apiKey = await secureStorage.getGoogleSearchApiKey(); 
  if (apiKey == null || apiKey.isEmpty) {
    printWithTimestamp('SecureStorageにGoogle Search APIキー (実質Geminiキー) が見つかりません。');
    return null; // .envからの読み込みは行わず、nullを返す
  }
  // SecureStorageにキーがあればそれを返す。再保存は不要。
  return apiKey;
});

// Google Programmable Search Engine IDを提供するProvider
final googleSearchEngineIdProvider = FutureProvider<String?>((ref) async {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  String? engineId = await secureStorage.getGoogleSearchEngineId();
  if (engineId == null || engineId.isEmpty) {
    printWithTimestamp('SecureStorageにGoogle Search Engine IDが見つかりません。');
    return null; // .envからの読み込みは行わず、nullを返す
  }
  // SecureStorageにキーがあればそれを返す。再保存は不要。
  return engineId;
});

// ImageSearchServiceのインスタンスを提供するProvider
final imageSearchServiceProvider = Provider<ImageSearchService?>((ref) {
  final apiKeyAsyncValue = ref.watch(googleSearchApiKeyProvider);
  final engineIdAsyncValue = ref.watch(googleSearchEngineIdProvider);

  return apiKeyAsyncValue.when(
    data: (apiKey) {
      return engineIdAsyncValue.when(
        data: (engineId) {
          if (apiKey != null && apiKey.isNotEmpty && engineId != null && engineId.isNotEmpty) {
            return ImageSearchService(apiKey: apiKey, searchEngineId: engineId);
          }
          printWithTimestamp('ImageSearchServiceプロバイダ: Google APIキーまたはEngine IDが不足しています。');
          return null;
        },
        loading: () => null, // または適切なローディング状態を示すオブジェクト
        error: (err, stack) {
          printWithTimestamp('ImageSearchServiceプロバイダ: Google Engine IDの読み込み中にエラー: $err');
          return null;
        },
      );
    },
    loading: () => null, // または適切なローディング状態を示すオブジェクト
    error: (err, stack) {
      printWithTimestamp('ImageSearchServiceプロバイダ: Google APIキーの読み込み中にエラー: $err');
      return null;
    },
  );
});

// データ処理ロジックを担当するProvider (例: KindleDataNotifier)
final kindleDataProvider = Provider<KindleDataNotifier>((ref) {
  return KindleDataNotifier(
    ref,
    ref.watch(csvParserProvider),
    ref.watch(databaseHelperProvider),
    ref.watch(bookListProvider.notifier),
    ref.watch(llmServiceProvider),
    ref.watch(imageSearchServiceProvider),
  );
});

class KindleDataNotifier {
  final Ref _ref;
  final CsvParser _csvParser;
  final DatabaseHelper _dbHelper;
  final BookListNotifier _bookListNotifier;
  final LlmService _llmService;
  final ImageSearchService? _imageSearchService;

  // ★追加: キャンセル用フラグ
  bool _isCancelled = false;

  // ★追加: キャンセルメソッド
  void cancelProcessing() {
    _isCancelled = true;
  }

  KindleDataNotifier(
    this._ref,
    this._csvParser, 
    this._dbHelper, 
    this._bookListNotifier, 
    this._llmService,
    this._imageSearchService,
  );

  // 新しいプライベートメソッド: 書籍のカバー画像を取得・保存する
  Future<String?> _fetchAndSaveCoverImageForBook(Book book) async {
    if (book.id == null) {
      printWithTimestamp('書籍IDがnullのため、カバー画像処理をスキップ: ${book.title}');
      return null;
    }
    if (_imageSearchService == null) {
      printWithTimestamp('ImageSearchServiceが初期化されていません。');
      _ref.read(processingStatusProvider.notifier).state = '画像検索サービスが利用できません。';
      return null;
    }

    try {
      final String searchQuery = await _llmService.generateImageSearchQuery(book.title, book.authors);
      if (searchQuery.isEmpty) {
        printWithTimestamp('書籍「${book.title}」の画像検索クエリが生成できませんでした。');
        _ref.read(processingStatusProvider.notifier).state = '画像検索クエリ生成失敗: ${book.title}';
        return null;
      }
      printWithTimestamp('書籍「${book.title}」の画像検索クエリ: $searchQuery');
      _ref.read(processingStatusProvider.notifier).state = '画像検索中: ${book.title} (クエリ: $searchQuery)';
      
      // 複数の画像候補を取得
      final List<String> imageUrls = await _imageSearchService.searchImages(searchQuery, numResults: 5);

      if (imageUrls.isEmpty) {
        printWithTimestamp('書籍「${book.title}」の画像がオンラインで見つかりませんでした。');
        _ref.read(processingStatusProvider.notifier).state = '画像が見つかりません: ${book.title}';
        return null;
      }
      printWithTimestamp('書籍「${book.title}」の画像URL候補 (${imageUrls.length}件): $imageUrls');

      final Dio dio = Dio();
      final directory = await getApplicationDocumentsDirectory();
      final String imageDirectoryPath = p.join(directory.path, 'covers');
      final Directory imageDir = Directory(imageDirectoryPath);
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }

      for (int i = 0; i < imageUrls.length; i++) {
        if (_isCancelled) {
          _ref.read(processingStatusProvider.notifier).state = '処理が中断されました';
          return null;
        }
        final String imageUrl = imageUrls[i];
        printWithTimestamp('試行 ${i + 1}/${imageUrls.length}: $imageUrl');
        _ref.read(processingStatusProvider.notifier).state = 
            '画像試行 ${i + 1}/${imageUrls.length}: ${book.title}';

        try {
          final response = await dio.get<Uint8List>(
            imageUrl,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 10)), // タイムアウト設定
          );

          if (response.statusCode == 200 && response.data != null) {
            final Uint8List imageData = response.data!;
            if (imageData.isEmpty) {
              printWithTimestamp('ダウンロードした画像データが空です: $imageUrl');
              continue; // 次のURLへ
            }

            // 画像データの有効性チェック
            try {
              // decodeImageFromListを使用して画像のデコードを試みる
              final ui.Image image = await decodeImageFromList(imageData);
              // デコード成功の確認 (特定のプロパティアクセスや追加の検証は不要な場合が多い)
              // image.width > 0 といった簡単なチェックも可能
              if (image.width == 0 || image.height == 0) { // 簡単なチェック
                printWithTimestamp('画像のデコードに失敗しました (width/height is 0): $imageUrl');
                image.dispose(); // 不要なリソースを解放
                continue;
              }
              printWithTimestamp('画像デコード成功: $imageUrl (w:${image.width}, h:${image.height})');
              image.dispose(); // 確認後、不要であればリソースを解放
            } catch (e) {
              printWithTimestamp('画像のデコード中にエラー: $imageUrl, エラー: $e');
              _ref.read(processingStatusProvider.notifier).state = 
                  '画像デコード失敗: ${book.title} (URL: ${imageUrl.substring(0,imageUrl.length > 50 ? 50 : imageUrl.length)})'; // URLを短縮表示 (50文字に制限)
              continue; // デコード失敗なら次のURLへ
            }
            
            // Content-Typeから拡張子を決定する方が望ましいが、ここではURLの拡張子を利用
            String fileExtension = p.extension(imageUrl).split('?').first;
            if (fileExtension.isEmpty || fileExtension.length > 5) { // あまりに長い拡張子や空の場合は.jpgにフォールバック
                // Content-Type ヘッダーから判断するロジックを追加するのが理想的
                // 例: response.headers.value('content-type') を見て 'image/jpeg' なら '.jpg'
                final contentType = response.headers.value(Headers.contentTypeHeader);
                if (contentType != null) {
                    if (contentType.contains('image/jpeg') || contentType.contains('image/jpg')) {
                        fileExtension = '.jpg';
                    } else if (contentType.contains('image/png')) {
                        fileExtension = '.png';
                    } else if (contentType.contains('image/gif')) {
                        fileExtension = '.gif';
                    } else if (contentType.contains('image/webp')) {
                        fileExtension = '.webp';
                    } else {
                        fileExtension = '.jpg'; // 不明な場合は .jpg
                    }
                } else {
                   fileExtension = '.jpg'; // Content-Typeがなければ .jpg
                }
            }


            final String newFileName = '${book.id}_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
            final String newFilePath = p.join(imageDirectoryPath, newFileName);
            
            final File newFile = File(newFilePath);
            await newFile.writeAsBytes(imageData);
            printWithTimestamp('書籍「${book.title}」の画像を保存しました: $newFilePath');
            _ref.read(processingStatusProvider.notifier).state = '画像保存完了: ${book.title}';

            // DBにも保存
            await _dbHelper.updateBookCoverImage(book.id!, newFilePath);
            // BookListNotifierにも通知してUIを更新
            final updatedBook = book.copyWith(coverImagePath: newFilePath);
            _bookListNotifier.updateSingleBookInList(updatedBook);

            return newFilePath; // 成功したらファイルパスを返す
          } else {
            printWithTimestamp('書籍「${book.title}」の画像ダウンロードに失敗しました。ステータス: ${response.statusCode}, URL: $imageUrl');
          }
        } catch (e, s) {
          printWithTimestamp('書籍「${book.title}」の画像処理中にエラー: $imageUrl, 詳細: $e');
          printWithTimestamp('スタックトレース: $s');
          // ここで処理状況を更新しても良い
        }
      } // end of for loop

      printWithTimestamp('書籍「${book.title}」の有効なカバー画像が見つかりませんでした。');
      _ref.read(processingStatusProvider.notifier).state = '有効な画像なし: ${book.title}';
      return null; // 全て試してダメだったらnullを返す

    } catch (e, s) {
      printWithTimestamp('書籍「${book.title}」のカバー画像取得・保存プロセス全体でエラー: $e');
      printWithTimestamp('スタックトレース: $s');
      _ref.read(processingStatusProvider.notifier).state = '画像処理エラー: ${book.title}';
      return null;
    }
  }

  Future<String> loadCsvAndSaveToDb({String? csvFileContent}) async {
    printWithTimestamp('[loadCsvAndSaveToDb] 開始');
    final stopwatch = Stopwatch()..start(); // 処理時間計測開始
    try {
      List<Book> booksFromCsv;
      printWithTimestamp('[loadCsvAndSaveToDb] CSVパース処理開始');
      if (csvFileContent != null && csvFileContent.isNotEmpty) {
        printWithTimestamp('[loadCsvAndSaveToDb] 提供されたCSVコンテンツからパースします。');
        booksFromCsv = await _csvParser.parseBooksFromCsvString(csvFileContent);
      } else {
        printWithTimestamp('[loadCsvAndSaveToDb] CSVファイルが提供されていません。');
        _ref.read(processingStatusProvider.notifier).state = 'CSVファイルが選択されていません。';
        return 'CSVファイルを選択してください。';
      }
      printWithTimestamp('[loadCsvAndSaveToDb] CSVパース処理完了。パースした書籍数: ${booksFromCsv.length}');

      if (booksFromCsv.isEmpty) {
        _ref.read(processingStatusProvider.notifier).state = 'CSVから書籍データが読み込めませんでした。';
        printWithTimestamp('[loadCsvAndSaveToDb] CSVから書籍データが読み込めませんでした。処理時間: ${stopwatch.elapsedMilliseconds}ms');
        return 'CSVから書籍データを読み込めませんでした（データが空かパース失敗）。';
      }

      printWithTimestamp('[loadCsvAndSaveToDb] DBバッチ挿入処理開始');
      await _dbHelper.batchInsertBooks(booksFromCsv);
      printWithTimestamp('[loadCsvAndSaveToDb] DBバッチ挿入処理完了');

      printWithTimestamp('[loadCsvAndSaveToDb] 書籍リスト再読み込み開始');
      await _bookListNotifier.loadBooks(); 
      printWithTimestamp('[loadCsvAndSaveToDb] 書籍リスト再読み込み完了');

      printWithTimestamp('[loadCsvAndSaveToDb] プロバイダー無効化開始 (uniqueGenresProvider, uniqueStatusesProvider)');
      _ref.invalidate(uniqueGenresProvider);
      _ref.invalidate(uniqueStatusesProvider);
      printWithTimestamp('[loadCsvAndSaveToDb] プロバイダー無効化完了');
      
      _ref.read(processingStatusProvider.notifier).state = '待機中';
      final successMessage = 'CSVから書籍を読み込みDB保存完了。DB内の書籍数: ${_bookListNotifier.state.length}';
      printWithTimestamp('[loadCsvAndSaveToDb] 成功終了。メッセージ: $successMessage, 処理時間: ${stopwatch.elapsedMilliseconds}ms');
      stopwatch.stop();
      return successMessage;
    } catch (e, s) { // エラーとスタックトレースをキャッチ
      _ref.read(processingStatusProvider.notifier).state = 'エラー（CSV/DB処理）';
      printWithTimestamp('[loadCsvAndSaveToDb] エラー発生。処理時間: ${stopwatch.elapsedMilliseconds}ms');
      printWithTimestamp('エラー詳細: $e');
      printWithTimestamp('スタックトレース: $s');
      stopwatch.stop();
      return 'CSV/DB処理中にエラーが発生しました: $e';
    }
  }

  Future<String> processBooksWithLlm({
    bool updateLlmInfo = true,
    bool updateImage = true,
    Function(String progress)? onProgress,
  }) async {
    _isCancelled = false; // 開始時にリセット
    try {
      final allBooks = await _dbHelper.getAllBooks();
      if (allBooks.isEmpty) {
        return 'データベースに書籍がありません。先にCSVから読み込んでください。';
      }

      int processedCount = 0; // LLMまたは画像処理の対象となった書籍の数
      int llmUpdatedCount = 0;
      int coverUpdatedCount = 0;
      int skippedCount = 0;
      
      final totalBooks = allBooks.length;
      onProgress?.call('LLM・画像一括処理開始: 全 $totalBooks 件');

      for (int i = 0; i < totalBooks; i++) {
        if (_isCancelled) {
          onProgress?.call('処理がユーザーにより中断されました。');
          _ref.read(processingStatusProvider.notifier).state = '処理が中断されました';
          return '処理がユーザーにより中断されました。';
        }
        final book = allBooks[i];
        Book currentBookData = book; // 更新を追跡するための書籍データ
        bool lSuccess = false;
        bool cSuccess = false;
        
        final bool needsLlmUpdate = book.id != null && 
                                    (book.genre == null || book.genre!.isEmpty || 
                                     book.keywords == null || book.keywords!.isEmpty);
        final bool needsCoverUpdate = book.id != null && 
                                      (book.coverImagePath == null || book.coverImagePath!.isEmpty);

        // どちらもfalseならスキップ
        if ((!updateLlmInfo || !needsLlmUpdate) && (!updateImage || !needsCoverUpdate)) {
          skippedCount++;
          onProgress?.call('(${(i + 1)}/$totalBooks)「${book.title}」は情報充足のためスキップ。');
          continue;
        }
        
        processedCount++;
        onProgress?.call('(${(i + 1)}/$totalBooks) 処理中: ${book.title}');
        printWithTimestamp('LLM・画像一括処理中 (${(i + 1)}/$totalBooks): ${book.title}');

        if (updateLlmInfo && needsLlmUpdate) {
          try {
            printWithTimestamp('  LLM情報取得開始: ${currentBookData.title}');
            final llmInfo = await _llmService.fetchBookInfoFromLlm(currentBookData.title);
            await _dbHelper.updateBookLlmInfo(currentBookData.id!, llmInfo['genre']!, llmInfo['keywords']!);
            currentBookData = currentBookData.copyWith(genre: llmInfo['genre']!, keywords: llmInfo['keywords']!);
            llmUpdatedCount++;
            lSuccess = true;
            printWithTimestamp('  書籍「${currentBookData.title}」のLLM情報を更新しました: ジャンル=${llmInfo['genre']}');
          } catch (e, s) {
            printWithTimestamp('  書籍「${currentBookData.title}」のLLM処理中にエラー: $e');
            printWithTimestamp('  スタックトレース: $s');
          }
        }

        if (updateImage && needsCoverUpdate) {
          try {
            printWithTimestamp('  カバー画像取得開始: ${currentBookData.title}');
            final newPath = await _fetchAndSaveCoverImageForBook(currentBookData);
            if (newPath != null) {
              currentBookData = currentBookData.copyWith(coverImagePath: newPath);
              coverUpdatedCount++;
              cSuccess = true;
              printWithTimestamp('  書籍「${currentBookData.title}」のカバー画像を更新しました。');
            }
          } catch (e, s) {
            printWithTimestamp('  書籍「${currentBookData.title}」のカバー画像処理中にエラー: $e');
            printWithTimestamp('  スタックトレース: $s');
          }
        }
         if(lSuccess || cSuccess){
          // メモリ上のリストも更新しておく（任意、最後に全ロードするので必須ではないが、進捗表示等で使うなら）
          // allBooks[i] = currentBookData; // 直接代入はできない final のため
        }
      }
      
      await _bookListNotifier.loadBooks(); // 最後にまとめてUIを更新
      final message = 'LLM・画像一括処理完了。処理対象: $processedCount 件 (うちLLM更新: $llmUpdatedCount 件, 画像更新: $coverUpdatedCount 件)。スキップ: $skippedCount 件。';
      onProgress?.call(message);
      _ref.read(processingStatusProvider.notifier).state = '待機中';
      _ref.invalidate(uniqueGenresProvider); // ジャンルプロバイダを無効化
      _ref.invalidate(uniqueStatusesProvider); // ステータスプロバイダも同様に無効化
      return message;
    } catch (e, s) {
      printWithTimestamp('LLM・画像一括処理全体でエラー: $e');
      printWithTimestamp('スタックトレース: $s');
      _ref.read(processingStatusProvider.notifier).state = 'エラー(LLM一括処理)';
      return 'LLM・画像一括処理中にエラーが発生しました。';
    }
  }

  Future<String> processSingleBookWithLlm(Book book, {Function(String progress)? onProgress}) async {
    if (book.id == null) {
      return 'エラー: 書籍IDがありません。';
    }
    // onProgress?.call('LLM処理開始: ${book.title}'); // UIへの表示は任意
    printWithTimestamp('LLM個別処理開始: ${book.title}');
    try {
      final llmInfo = await _llmService.fetchBookInfoFromLlm(book.title);
      await _dbHelper.updateBookLlmInfo(book.id!, llmInfo['genre']!, llmInfo['keywords']!);
      await _bookListNotifier.loadBooks(); // UIを更新
      _ref.invalidate(uniqueGenresProvider); // ジャンルプロバイダを無効化
      _ref.invalidate(uniqueStatusesProvider); // ステータスプロバイダも同様に無効化
      final message = '書籍「${book.title}」の情報をLLMで更新しました。';
      onProgress?.call(message); // 成功メッセージはUIに表示
      return message;
    } catch (e, s) { // スタックトレースも受け取る
      printWithTimestamp('書籍「${book.title}」のLLM処理(個別)中にエラー: $e');
      printWithTimestamp('スタックトレース: $s'); // スタックトレースをコンソールに出力
      // onProgress?.call('個別エラー: ${book.title} - $e'); // UIへのエラー詳細表示をコメントアウト
      return '書籍「${book.title}」のLLM処理中にエラーが発生しました。'; // UIには簡潔なエラーメッセージを返す
    }
  }

  Future<String> toggleBookStatus(Book book, WidgetRef ref) async {
    if (book.id == null) {
      return 'エラー: 書籍IDがありません。';
    }
    try {
      final currentStatus = book.status;
      final newStatus = currentStatus == 'READ' ? 'UNKNOWN' : 'READ';

      await _dbHelper.updateBookStatus(book.id!, newStatus);
      // 書籍リスト内の該当書籍のステータスを更新
      await _bookListNotifier.loadBooks(); // DBから再読み込みしてリストを更新
      
      ref.invalidate(uniqueStatusesProvider); // ステータスリストを更新するために無効化

      return '書籍「${book.title}」のステータスを $newStatus に更新しました。';
    } catch (e) {
      printWithTimestamp('書籍「${book.title}」のステータス更新中にエラー: $e');
      return '書籍「${book.title}」のステータス更新中にエラーが発生しました: $e';
    }
  }

  Future<String> pickAndSaveCoverImage(Book book, WidgetRef ref) async {
    if (book.id == null) {
      return 'エラー: 書籍IDがありません。';
    }

    try {
      // 1. ファイルピッカーで画像を選択
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null && result.files.single.path != null) {
        File pickedFile = File(result.files.single.path!);

        // 2. アプリのドキュメントディレクトリを取得
        final directory = await getApplicationDocumentsDirectory();
        final String imageDirectoryPath = p.join(directory.path, 'covers');
        final Directory imageDir = Directory(imageDirectoryPath);
        if (!await imageDir.exists()) {
          await imageDir.create(recursive: true);
        }

        // 3. 新しいファイル名を生成 (例: bookId_timestamp.ext)
        final String fileExtension = p.extension(pickedFile.path);
        final String newFileName = '${book.id}_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
        final String newFilePath = p.join(imageDirectoryPath, newFileName);

        // 4. 選択されたファイルをアプリディレクトリにコピー
        await pickedFile.copy(newFilePath);

        // 5. データベースに新しい画像パスを保存
        await _dbHelper.updateBookCoverImage(book.id!, newFilePath);

        // 6. 書籍リストを更新 (全件ロードではなく、該当書籍のみ更新)
        final updatedBook = book.copyWith(coverImagePath: newFilePath);
        await _bookListNotifier.updateSingleBookInList(updatedBook);
        // ref.invalidate(bookListProvider); // updateSingleBookInListでstateが更新されるので不要かも

        return '書籍「${book.title}」のカバー画像を更新しました。';
      } else {
        return '画像が選択されませんでした。';
      }
    } catch (e) {
      printWithTimestamp('カバー画像の選択または保存中にエラー: $e');
      return 'カバー画像の処理中にエラーが発生しました: $e';
    }
  }

  // 新しいメソッド: オンラインで画像を検索し、ユーザーに選択させて保存する (UI部分は別途実装)
  Future<String> searchAndPickCoverImageOnline(Book book, WidgetRef ref) async {
    if (book.id == null) return 'エラー: 書籍IDがありません。';
    _ref.read(processingStatusProvider.notifier).state = 'オンライン画像検索開始: ${book.title}';

    try {
      // 修正: _fetchAndSaveCoverImageForBook を呼び出して処理を一任する
      final String? newPath = await _fetchAndSaveCoverImageForBook(book);

      if (newPath != null) {
        _ref.read(processingStatusProvider.notifier).state = '待機中（オンライン画像取得完了: ${book.title}）';
        return '書籍「${book.title}」のカバー画像をオンラインで取得・更新しました。';
      } else {
        // _fetchAndSaveCoverImageForBook内でstatusProviderは更新されているはずなので、ここでは簡潔に
        // ref.read(processingStatusProvider.notifier).state = '待機中（オンライン画像取得失敗: ${book.title}）'; 
        printWithTimestamp('searchAndPickCoverImageOnline: _fetchAndSaveCoverImageForBook から有効なパスが返されませんでした。');
        return 'オンラインで有効なカバー画像が見つかりませんでした。';
      }
    } catch (e, s) {
      printWithTimestamp('searchAndPickCoverImageOnline でエラー: $e');
      printWithTimestamp('スタックトレース: $s');
      _ref.read(processingStatusProvider.notifier).state = 'エラー（オンライン画像検索）';
      return 'オンラインでのカバー画像処理中にエラーが発生しました: $e';
    }
  }
}

// --- ここからフィルタ関連のProvider定義 ---

// フィルタ条件を表すクラス
class BookFilter {
  final String? genre;
  final String? status;
  final String? titleKeyword;
  final DateTimeRange? purchaseDateRange; // 購入日フィルタ用

  BookFilter({
    this.genre,
    this.status,
    this.titleKeyword,
    this.purchaseDateRange,
  });

  // ジャンル文字列をパースしてリストで返すゲッター
  List<String> get parsedGenres {
    if (genre == null || genre!.trim().isEmpty) {
      return [];
    }
    // 読点「、」とカンマ「,」で分割し、各要素をトリムして空でなければリストに追加
    return genre!
        .split(RegExp(r'[、,]')) // 読点またはカンマで分割
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toList();
  }

  // フィルタがアクティブかどうかを判定するヘルパー
  bool get isActive =>
      (parsedGenres.isNotEmpty) || // genre があるかどうかは parsedGenres で判定
      (status != null && status!.isNotEmpty) ||
      (titleKeyword != null && titleKeyword!.isNotEmpty) ||
      purchaseDateRange != null;

  // フィルタ条件をクリアした新しいインスタンスを返す
  BookFilter clear() {
    return BookFilter();
  }

  BookFilter copyWith({
    String? genre,
    String? status,
    String? titleKeyword,
    DateTimeRange? purchaseDateRange,
    bool clearPurchaseDate = false, // 日付範囲を明示的にnullにするためのフラグ
  }) {
    return BookFilter(
      genre: genre ?? this.genre,
      status: status ?? this.status,
      titleKeyword: titleKeyword ?? this.titleKeyword,
      purchaseDateRange: clearPurchaseDate ? null : purchaseDateRange ?? this.purchaseDateRange,
    );
  }
}

// フィルタ条件を管理するStateProvider
final bookFilterProvider = StateProvider<BookFilter>((ref) => BookFilter());

// DBからユニークなジャンルリストを取得するProvider
final uniqueGenresProvider = FutureProvider<List<String>>((ref) async {
  final dbHelper = ref.watch(databaseHelperProvider);
  return await dbHelper.getUniqueGenres();
});

// DBからユニークなステータスリストを取得するProvider
final uniqueStatusesProvider = FutureProvider<List<String>>((ref) async {
  final dbHelper = ref.watch(databaseHelperProvider);
  return await dbHelper.getUniqueStatuses();
});

// フィルタリングされた書籍リストを提供するProvider
final filteredBookListProvider = Provider<List<Book>>((ref) {
  final allBooks = ref.watch(bookListProvider);
  final filter = ref.watch(bookFilterProvider);

  if (!filter.isActive) {
    return allBooks;
  }

  return allBooks.where((book) {
    bool matches = true;
    
    // ジャンルフィルタ (OR検索)
    if (filter.parsedGenres.isNotEmpty) {
      if (book.genre == null || book.genre!.trim().isEmpty) {
        matches = matches && false; // 書籍にジャンルがなければマッチしない
      } else {
        final bookGenres = book.genre!
            .split(RegExp(r'[、,]'))
            .map((g) => g.trim().toLowerCase())
            .where((g) => g.isNotEmpty)
            .toSet(); // 高速なルックアップのためにSetに変換
        
        // フィルタで指定されたジャンルのいずれかが、書籍のジャンルに含まれているか
        matches = matches && filter.parsedGenres.any((filterGenre) => bookGenres.contains(filterGenre.toLowerCase()));
      }
    }

    // ステータスフィルタ
    if (filter.status != null && filter.status!.isNotEmpty) {
      matches = matches && (book.status.toLowerCase() == filter.status!.toLowerCase());
    }
    // タイトルキーワードフィルタ
    if (filter.titleKeyword != null && filter.titleKeyword!.isNotEmpty) {
      matches = matches && (book.title.toLowerCase().contains(filter.titleKeyword!.toLowerCase()));
    }
    // 購入日範囲フィルタ
    if (filter.purchaseDateRange != null) {
      try {
        // book.purchaseDate は "YYYY/MM/DD" 形式と仮定
        final purchaseDate = DateFormat('yyyy/MM/dd').parse(book.purchaseDate);
        matches = matches &&
            !purchaseDate.isBefore(filter.purchaseDateRange!.start) &&
            !purchaseDate.isAfter(filter.purchaseDateRange!.end.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1))); // end はその日の終わりまで含むように調整
      } catch (e) {
        printWithTimestamp("日付パースエラー: ${book.purchaseDate} - $e");
        matches = matches && false; // パース失敗時はフィルタにマッチしない
      }
    }
    return matches;
  }).toList();
});

// 処理結果メッセージ表示用 (CSV/DB処理)
final processingStatusProvider = StateProvider<String>((ref) => '');

// LLM処理の進捗メッセージを管理するProvider
final llmProcessingProgressProvider = StateProvider<String>((ref) => ''); 