import 'dart:io'; // Fileクラス使用のため

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart'; // 日付フォーマットのため
import 'package:kindle_reader/data/csv_parser.dart'; // Bookモデルをインポート
import 'package:kindle_reader/utils/logger.dart';

import 'providers.dart';
import 'screens/settings_screen.dart'; // 後で作成する設定画面

// ボトムナビゲーションの選択中インデックスを管理
final selectedPageIndexProvider = StateProvider<int>((ref) => 0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await dotenv.load(fileName: ".env");
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // アプリ起動時に書籍データをロード
    // initState内ではref.watchは使えないため、ref.readを使用します。
    // また、この処理はUIのビルドとは直接関係ないため、readで問題ありません。
    _loadBooks().then((_) {
      // ignore: avoid_print
      print('データベースから書籍データをロードしました。');
      // 必要であれば、ロード完了後に特定の状態を更新したり、エラーハンドリングを行う
    }).catchError((error) {
      // ignore: avoid_print
      print('書籍データのロード中にエラーが発生しました: $error');
    });
  }

  Future<void> _loadBooks() async {
    try {
      await ref.read(bookListProvider.notifier).loadBooks();
      printWithTimestamp('データベースから書籍データをロードしました。');
    } catch (error) {
      printWithTimestamp('書籍データのロード中にエラーが発生しました: $error');
      // エラーハンドリング（例: SnackBarでユーザーに通知）
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kindle Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // ExpansionPanelListの見た目を調整
        expansionTileTheme: const ExpansionTileThemeData(
          iconColor: Colors.blue,
          textColor: Colors.blue,
        )
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends ConsumerWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPageIndex = ref.watch(selectedPageIndexProvider);
    // 書籍一覧画面で必要なデータはここでwatchしておく
    final filteredBooks = ref.watch(filteredBookListProvider);
    final kindleDataNotifier = ref.read(kindleDataProvider); // これはボタン操作等で使うのでreadで良い場合も
    final processingStatus = ref.watch(processingStatusProvider); // 書籍一覧画面で表示
    final llmProcessingStatus = ref.watch(llmProcessingProgressProvider); // 書籍一覧画面で表示
    final filter = ref.watch(bookFilterProvider);

    // 各画面のウィジェットリスト
    final List<Widget> pageWidgets = [
      _BookListPage(), // 書籍一覧ページを別ウィジェットとして定義
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: null,
        actions: [
          if (selectedPageIndex == 0) // 書籍一覧画面の時だけフィルタアイコンを表示
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'フィルタ',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (BuildContext context) {
                    return const _FilterPanelView(); // これは変更なし
                  },
                );
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: selectedPageIndex,
        children: pageWidgets,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: '書籍一覧',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
        currentIndex: selectedPageIndex,
        selectedItemColor: Colors.blue,
        onTap: (index) {
          ref.read(selectedPageIndexProvider.notifier).state = index;
        },
      ),
    );
  }
}

// 書籍一覧ページ専用のウィジェット
class _BookListPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredBooks = ref.watch(filteredBookListProvider);
    final kindleDataNotifier = ref.read(kindleDataProvider);
    final processingStatus = ref.watch(processingStatusProvider);
    final llmProcessingStatus = ref.watch(llmProcessingProgressProvider);
    final filter = ref.watch(bookFilterProvider);

    return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 以前ここにボタンがあったが設定画面へ移動
            // 処理状況表示はここに残す
            Text('処理状況 (CSV/DB): $processingStatus'),
            const SizedBox(height: 5),
            Text('処理状況 (LLM): $llmProcessingStatus'),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                  Text(
                  '書籍一覧 (${filteredBooks.length}件):',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (filter.isActive)
                  TextButton.icon(
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: const Text('フィルタ解除', style: TextStyle(fontSize: 12)),
                    onPressed: () => ref.read(bookFilterProvider.notifier).state = filter.clear(),
                  )
              ],
            ),
            const SizedBox(height: 8),
            // 書籍リスト
            Expanded(
              child: filteredBooks.isEmpty
                  ? const Center(child: Text('該当する書籍データがありません。'))
                  : ListView.builder(
                      itemCount: filteredBooks.length,
                      itemBuilder: (context, index) {
                        final book = filteredBooks[index];
                        Widget leadingWidget;
                        if (book.coverImagePath != null && book.coverImagePath!.isNotEmpty) {
                          final imageFile = File(book.coverImagePath!);
                          if (imageFile.existsSync()) {
                            leadingWidget = SizedBox(
                              width: 50,
                              height: 70,
                              child: Image.file(
                                imageFile, 
                                fit: BoxFit.cover,
                                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                                  // 画像のロードに失敗した場合のフォールバックUI
                                  printWithTimestamp(
                                      'Error loading image ${book.coverImagePath}: $error');
                                  return Container(
                                    width: 50,
                                    height: 70,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.broken_image, size: 40),
                                  );
                                },
                              ),
                            );
                          } else {
                            leadingWidget = const Icon(Icons.broken_image, size: 40); // ファイルが存在しない場合
                          }
                        } else {
                          leadingWidget = const Icon(Icons.image_not_supported, size: 40); // パスがない場合
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          child: ListTile(
                            leading: leadingWidget,
                            title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (book.authors.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0, bottom: 2.0),
                                    child: Text(book.authors, style: const TextStyle(fontSize: 13)),
                                  ),
                              ],
                            ),
                            onTap: () {
                              _showBookDetails(context, book, ref);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final result = await kindleDataNotifier.toggleBookStatus(book, ref); 
                                    ref.read(processingStatusProvider.notifier).state = result;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(milliseconds: 1500)));
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
                                    decoration: BoxDecoration(
                                      color: book.status == 'READ' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4.0),
                                      border: Border.all(
                                        color: book.status == 'READ' ? Colors.green : Colors.orange,
                                        width: 0.5,
                                      )
                                    ),
                                    child: Text(
                                      book.status == 'UNKNOWN' ? '未読' : (book.status == 'READ' ? '読了' : book.status),
                                      style: TextStyle(
                                        color: book.status == 'READ' ? Colors.green : Colors.deepOrangeAccent,
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.image_search_outlined, size: 22),
                                  tooltip: 'カバー画像をオンライン検索',
                                  onPressed: () async {
                                    ref.read(processingStatusProvider.notifier).state = 'オンラインで画像を検索中...';
                                    final result = await kindleDataNotifier.searchAndPickCoverImageOnline(book, ref);
                                    ref.read(processingStatusProvider.notifier).state = result;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.psychology_alt_outlined, size: 22),
                                  tooltip: 'LLMでこの書籍の情報を取得・更新',
                                  onPressed: () async {
                                    ref.read(processingStatusProvider.notifier).state = '個別LLM処理を開始...';
                                    final result = await kindleDataNotifier.processSingleBookWithLlm(
                                      book,
                                      onProgress: (progress) {
                                        ref.read(llmProcessingProgressProvider.notifier).state = progress;
                                      },
                                    );
                                    ref.read(processingStatusProvider.notifier).state = result;
                                    ref.invalidate(uniqueGenresProvider);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
                                  },
                                ),
                              ],
                            ),
                            isThreeLine: book.genre != null && book.genre!.isNotEmpty && book.keywords != null && book.keywords!.isNotEmpty, 
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
  }
}

// 書籍詳細をボトムシートに表示するためのメソッド
void _showBookDetails(BuildContext context, Book book, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true, // 内容が多い場合にスクロール可能にする
    shape: const RoundedRectangleBorder( // 上部の角を丸める
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext bc) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6, // 初期表示の高さを画面の60%に
        minChildSize: 0.4,     // 最小の高さを画面の40%に
        maxChildSize: 0.9,     // 最大の高さを画面の90%に
        builder: (_, controller) {
          return _BookDetailsSheet(book: book, scrollController: controller, ref: ref);
        },
      );
    },
  );
}

// 書籍詳細表示用のウィジェット
class _BookDetailsSheet extends ConsumerWidget {
  final Book book;
  final ScrollController scrollController;
  final WidgetRef ref; // KindleDataNotifierを使用するためにWidgetRefを渡す

  const _BookDetailsSheet({
    super.key,
    required this.book,
    required this.scrollController,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef consumerRef) { // WidgetRefはbuildメソッドの引数でも受け取れる
    final kindleDataNotifier = ref.read(kindleDataProvider); // ここでref（コンストラクタ経由）を使用
    String purchaseDateFormatted;
    if (book.purchaseDate.isNotEmpty) {
      try {
        // まず "yyyy年MM月dd日" 形式でのパースを試みる (エラーメッセージに合致)
        DateTime dt = DateFormat('yyyy年MM月dd日').parse(book.purchaseDate);
        purchaseDateFormatted = DateFormat('yyyy年MM月dd日').format(dt); // 再度フォーマット (一貫性のため)
      } catch (e1) {
        try {
          // 次に標準の DateTime.parse を試みる (例: "yyyy-MM-dd")
          DateTime dt = DateTime.parse(book.purchaseDate);
          purchaseDateFormatted = DateFormat('yyyy年MM月dd日').format(dt);
        } catch (e2) {
          // 両方のパースに失敗した場合
          printWithTimestamp(
              "日付の解析に失敗しました: ${book.purchaseDate}. Error1: $e1, Error2: $e2");
          purchaseDateFormatted = book.purchaseDate; // フォールバックとして元の文字列を表示
        }
      }
    } else {
      purchaseDateFormatted = "日付なし"; // 空の日付文字列の場合
    }

    return Container(
      padding: const EdgeInsets.all(20.0),
      child: SingleChildScrollView(
        controller: scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // カバー画像
            if (book.coverImagePath != null && book.coverImagePath!.isNotEmpty)
              Center(
                child: GestureDetector(
                  onTap: () async {
                    // 画像をタップしたらローカルから画像を選択して更新
                    final result = await kindleDataNotifier.pickAndSaveCoverImage(book, ref);
                    Navigator.pop(context); // ボトムシートを閉じる
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result), duration: const Duration(milliseconds: 2000)),
                    );
                  },
                  onLongPress: () async {
                    // 画像を長押ししたらオンラインで画像を検索して更新
                     final scaffoldMessenger = ScaffoldMessenger.of(context); // Local context for ScaffoldMessenger
                     final navigator = Navigator.of(context); // Local context for Navigator

                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('オンラインで画像を検索・設定します...'), duration: Duration(seconds: 2)),
                    );
                    final result = await kindleDataNotifier.searchAndPickCoverImageOnline(book, ref);
                    // ボトムシートがまだ表示されていれば閉じる
                    if (navigator.canPop()) {
                       navigator.pop();
                    }
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text(result), duration: const Duration(milliseconds: 2500)),
                    );
                  },
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Image.file(
                        File(book.coverImagePath!),
                        height: 250,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          printWithTimestamp('Cover image load error for ${book.title}: $error');
                          return Container(
                            height: 220,
                            width: 150,
                            color: Colors.grey[300],
                            child: const Center(child: Icon(Icons.broken_image, size: 60, color: Colors.grey)),
                          );
                        },
                      ),
                      Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            if (book.coverImagePath == null || book.coverImagePath!.isEmpty)
              Center(
                child: GestureDetector(
                   onTap: () async {
                    // 画像をタップしたらローカルから画像を選択して更新
                    final result = await kindleDataNotifier.pickAndSaveCoverImage(book, ref);
                    Navigator.pop(context); // ボトムシートを閉じる
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result), duration: const Duration(milliseconds: 2000)),
                    );
                  },
                  onLongPress: () async {
                    // 画像を長押ししたらオンラインで画像を検索して更新
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);

                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('オンラインで画像を検索・設定します...'), duration: Duration(seconds: 2)),
                    );
                    final result = await kindleDataNotifier.searchAndPickCoverImageOnline(book, ref);
                     if (navigator.canPop()) {
                       navigator.pop();
                    }
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text(result), duration: const Duration(milliseconds: 2500)),
                    );
                  },
                  child: Container(
                    height: 220,
                    width: 150, // ある程度の幅を持たせる
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[400]!),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_not_supported, size: 60, color: Colors.grey),
                          SizedBox(height: 8),
                          Text("タップして画像設定", style: TextStyle(color: Colors.grey)),
                          Text("長押しでオンライン検索", style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),

            _buildDetailItem('タイトル', book.title),
            _buildDetailItem('著者', book.authors),
            _buildDetailItem('購入日', purchaseDateFormatted),
            _buildDetailItem('ステータス', book.status == 'UNKNOWN' ? '未読' : (book.status == 'READ' ? '読了' : book.status), 
              highlight: true, 
              color: book.status == 'READ' ? Colors.green : Colors.orange
            ),
            _buildDetailItem('ジャンル', book.genre ?? '未設定'),
            _buildDetailItem('キーワード', book.keywords?.isNotEmpty == true ? book.keywords! : '未設定'),
            
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ),
            const SizedBox(height: 10), // 下部の余白
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {bool highlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80, // ラベルの幅を固定
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// フィルタパネルのUIを定義する新しいウィジェット
class _FilterPanelView extends ConsumerStatefulWidget {
  const _FilterPanelView({super.key});

  @override
  ConsumerState<_FilterPanelView> createState() => _FilterPanelViewState();
}

class _FilterPanelViewState extends ConsumerState<_FilterPanelView> {
  late TextEditingController _genreController;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(bookFilterProvider);
    _genreController = TextEditingController(text: filter.genre ?? '');
  }

  @override
  void dispose() {
    _genreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bookFilterProvider);
    final filterNotifier = ref.read(bookFilterProvider.notifier);
    final uniqueGenresAsyncValue = ref.watch(uniqueGenresProvider);
    final uniqueStatusesAsyncValue = ref.watch(uniqueStatusesProvider);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('フィルタ', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 16),
            // タイトル検索欄を復活
            TextField(
              decoration: const InputDecoration(
                labelText: 'タイトル検索',
                hintText: 'キーワードを入力',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (value) {
                filterNotifier.state = filter.copyWith(titleKeyword: value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _genreController,
              decoration: const InputDecoration(
                labelText: 'ジャンル（カンマ・読点区切り可）',
                hintText: '例: 小説, 趣味、実用',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (value) {
                filterNotifier.state = filter.copyWith(genre: value);
              },
            ),
            const SizedBox(height: 8),
            uniqueGenresAsyncValue.when(
              data: (genres) => DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'ジャンル候補から追加',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                value: null,
                hint: const Text('選択して追加'),
                isExpanded: true,
                items: genres.map((genre) => DropdownMenuItem(
                  value: genre,
                  child: Text(genre),
                )).toList(),
                onChanged: (value) {
                  if (value != null && value.isNotEmpty) {
                    final current = _genreController.text;
                    final genresList = current.split(RegExp(r'[、,]')).map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
                    if (!genresList.contains(value)) {
                      final newText = (current.isEmpty) ? value : '$current, $value';
                      _genreController.text = newText;
                      filterNotifier.state = filter.copyWith(genre: newText);
                    }
                  }
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Text('ジャンル読込エラー: $err'),
            ),
            const SizedBox(height: 12),
            uniqueStatusesAsyncValue.when(
              data: (statuses) => DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'ステータス',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                value: filter.status,
                hint: const Text('すべて'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String>(
                    value: null, 
                    child: Text('すべて'),
                  ),
                  ...statuses.map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      )),
                ],
                onChanged: (value) {
                  filterNotifier.state = filter.copyWith(status: value);
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Text('ステータス読込エラー: $err'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(
                filter.purchaseDateRange == null
                    ? '購入日フィルタ (すべて)'
                    : '${DateFormat('yyyy/MM/dd').format(filter.purchaseDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(filter.purchaseDateRange!.end)}',
              ),
              onPressed: () async {
                final pickedDateRange = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: filter.purchaseDateRange,
                );
                if (pickedDateRange != null) {
                  filterNotifier.state = filter.copyWith(purchaseDateRange: pickedDateRange);
                } else if (filter.purchaseDateRange != null) {
                  filterNotifier.state = filter.copyWith(clearPurchaseDate: true);
                }
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                filterNotifier.state = filter.clear();
                Navigator.pop(context); // クリアしたら閉じる
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300]),
              child: const Text('フィルタをクリアして閉じる', style: TextStyle(color: Colors.black87)),
            ),
            // 以前の「閉じる」ボタンはフィルタパネルのヘッダーに移動
          ],
        ),
      ),
    );
  }
}

// 処理結果メッセージ表示用 (CSV/DB処理)
// final processingStatusProvider = StateProvider<String>((ref) => ''); // providers.dart に移動

// LLM処理の進捗メッセージを管理するProvider
// final llmProcessingProgressProvider = StateProvider<String>((ref) => ''); // providers.dart に移動
