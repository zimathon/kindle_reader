import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kindle Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends ConsumerWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(bookListProvider);
    final kindleDataNotifier = ref.read(kindleDataProvider);
    final processingStatus = ref.watch(processingStatusProvider);
    final llmProcessingStatus = ref.watch(llmProcessingProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kindle Book Manager'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    ref.read(processingStatusProvider.notifier).state = 'CSV処理中...';
                    ref.read(llmProcessingProgressProvider.notifier).state = '';
                    final result = await kindleDataNotifier.loadCsvAndSaveToDb();
                    ref.read(processingStatusProvider.notifier).state = result;
                  },
                  child: const Text('CSV読み込み & DB保存'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    ref.read(processingStatusProvider.notifier).state = 'LLM処理を開始します...';
                    ref.read(llmProcessingProgressProvider.notifier).state = '準備中...';
                    final result = await kindleDataNotifier.processBooksWithLlm(
                      onProgress: (progress) {
                        ref.read(llmProcessingProgressProvider.notifier).state = progress;
                      },
                    );
                    ref.read(processingStatusProvider.notifier).state = result;
                  },
                  child: const Text('LLMで書籍情報更新'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await ref.read(bookListProvider.notifier).clearBooks();
                ref.read(processingStatusProvider.notifier).state = 'DB全件削除 & 書籍リストをクリアしました。';
                ref.read(llmProcessingProgressProvider.notifier).state = '';
              },
              child: const Text('DB全件削除 & リストクリア'),
            ),
            const SizedBox(height: 20),
            Text('処理状況 (CSV/DB): $processingStatus'),
            const SizedBox(height: 5),
            Text('処理状況 (LLM): $llmProcessingStatus'),
            const SizedBox(height: 10),
            Text('DB内の書籍数: ${books.length}'),
            const SizedBox(height: 20),
            const Text(
              '書籍一覧:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: books.isEmpty
                  ? const Center(child: Text('書籍データがありません。'))
                  : ListView.builder(
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final book = books[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          child: ListTile(
                            title: Text(book.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(book.authors),
                                if (book.genre != null && book.genre!.isNotEmpty)
                                  Text('ジャンル: ${book.genre}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                if (book.keywords != null && book.keywords!.isNotEmpty)
                                  Text('キーワード: ${book.keywords}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(book.status, style: TextStyle(color: book.status == 'READ' ? Colors.green : Colors.orange )),
                                IconButton(
                                  icon: const Icon(Icons.smart_toy_outlined),
                                  tooltip: 'LLMで情報取得',
                                  onPressed: () async {
                                    ref.read(processingStatusProvider.notifier).state = '個別LLM処理を開始...';
                                    final result = await kindleDataNotifier.processSingleBookWithLlm(
                                      book,
                                      onProgress: (progress) {
                                        ref.read(llmProcessingProgressProvider.notifier).state = progress;
                                      },
                                    );
                                    ref.read(processingStatusProvider.notifier).state = result;
                                  },
                                ),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// 処理結果メッセージ表示用 (CSV/DB処理)
final processingStatusProvider = StateProvider<String>((ref) => '');

// LLM処理の進捗メッセージを管理するProvider
final llmProcessingProgressProvider = StateProvider<String>((ref) => '');
