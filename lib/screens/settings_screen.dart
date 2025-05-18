import 'dart:io'; // Fileクラスのため

import 'package:file_picker/file_picker.dart'; // file_picker をインポート
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kindle_reader/utils/logger.dart';

import '../providers.dart'; // KindleDataProviderなどを参照するため

// SettingsScreen を ConsumerStatefulWidget に変更
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _selectedCsvFileName;
  String? _selectedCsvFileContent;

  // APIキー入力用コントローラー
  late TextEditingController _geminiApiKeyController;
  late TextEditingController _googleSearchApiKeyController;
  late TextEditingController _googleSearchEngineIdController;

  bool _isLoadingApiKeys = true; // APIキー読み込み中のフラグ

  // ★追加: LLM/画像更新のチェックボックス用
  bool _updateLlmInfo = true;
  bool _updateImage = true;

  @override
  void initState() {
    super.initState();
    _geminiApiKeyController = TextEditingController();
    _googleSearchApiKeyController = TextEditingController();
    _googleSearchEngineIdController = TextEditingController();
    _loadApiKeys();
  }

  Future<void> _loadApiKeys() async {
    final secureStorage = ref.read(secureStorageServiceProvider);
    final geminiKey = await secureStorage.getGeminiApiKey();
    final googleSearchKey = await secureStorage.getGoogleSearchApiKey();
    final googleEngineId = await secureStorage.getGoogleSearchEngineId();

    if (mounted) {
      setState(() {
        _geminiApiKeyController.text = geminiKey ?? '';
        _googleSearchApiKeyController.text = googleSearchKey ?? '';
        _googleSearchEngineIdController.text = googleEngineId ?? '';
        _isLoadingApiKeys = false;
      });
    }
  }

  @override
  void dispose() {
    _geminiApiKeyController.dispose();
    _googleSearchApiKeyController.dispose();
    _googleSearchEngineIdController.dispose();
    super.dispose();
  }

  Future<void> _pickCsvFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        final filePath = result.files.single.path;
        if (filePath != null) {
          final file = File(filePath);
          final content = await file.readAsString();
          setState(() {
            _selectedCsvFileName = result.files.single.name;
            _selectedCsvFileContent = content;
          });
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CSVファイル「${result.files.single.name}」を準備しました。\n「選択したCSVでDB保存」ボタンを押してください。')),
          );
        } else {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ファイルパスが取得できませんでした。')),
          );
          setState(() { // ファイルパスがnullの場合も選択状態をリセット
            _selectedCsvFileName = null;
            _selectedCsvFileContent = null;
          });
        }
      } else {
        printWithTimestamp('CSVファイルの選択がキャンセルされました。');
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSVファイルの選択がキャンセルされました。')),
        );
        setState(() { // キャンセル時も選択状態をリセット
          _selectedCsvFileName = null;
          _selectedCsvFileContent = null;
        });
      }
    } catch (e) {
      printWithTimestamp('CSVファイル選択中にエラー: $e');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSVファイル選択エラー: $e')),
      );
      setState(() { // エラー時は選択状態をリセット
        _selectedCsvFileName = null;
        _selectedCsvFileContent = null;
      });
    }
  }

  Future<void> _saveApiKeys() async {
    final secureStorage = ref.read(secureStorageServiceProvider);
    final geminiApiKey = _geminiApiKeyController.text.trim();
    final googleSearchApiKey = _googleSearchApiKeyController.text.trim();
    final googleSearchEngineId = _googleSearchEngineIdController.text.trim();

    await secureStorage.saveGeminiApiKey(geminiApiKey);
    await secureStorage.saveGoogleSearchApiKey(googleSearchApiKey);
    await secureStorage.saveGoogleSearchEngineId(googleSearchEngineId);

    // Providerを無効化して新しいキーを読み込ませる
    ref.invalidate(geminiApiKeyProvider);
    ref.invalidate(googleSearchApiKeyProvider);
    ref.invalidate(googleSearchEngineIdProvider);

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('APIキーを保存しました。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kindleDataNotifier = ref.read(kindleDataProvider);
    final processingStatusNotifier = ref.read(processingStatusProvider.notifier);
    final bookListNotifier = ref.read(bookListProvider.notifier);

    // LLM処理の進捗をwatchで監視
    final llmProgress = ref.watch(llmProcessingProgressProvider);
    final overallStatus = ref.watch(processingStatusProvider); // 全体ステータスも監視

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        automaticallyImplyLeading: false, // ボトムナビで表示するので戻るボタンは不要
      ),
      body: _isLoadingApiKeys 
          ? const Center(child: CircularProgressIndicator()) 
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // ボタンを幅いっぱいに広げる
          children: <Widget>[
            const Text(
              'データ管理',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('CSVファイルを選択 (.csv)'),
              onPressed: _pickCsvFile,
            ),
            if (_selectedCsvFileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('選択中: $_selectedCsvFileName', style: const TextStyle(color: Colors.green)),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('選択したCSVでDB保存'),
              onPressed: _selectedCsvFileContent != null ? () async {
                processingStatusNotifier.state = 'CSV処理中...';
                final result = await kindleDataNotifier.loadCsvAndSaveToDb(csvFileContent: _selectedCsvFileContent);
                processingStatusNotifier.state = result;
                ref.invalidate(uniqueGenresProvider);
                ref.invalidate(uniqueStatusesProvider);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
              } : null,
            ),
            const SizedBox(height: 12),
            // ★追加: LLM/画像更新のチェックボックス
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _updateLlmInfo,
                      onChanged: (val) => setState(() => _updateLlmInfo = val!),
                    ),
                    const Text('ジャンル'),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _updateImage,
                      onChanged: (val) => setState(() => _updateImage = val!),
                    ),
                    const Text('画像'),
                  ],
                ),
              ],
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('LLMで全書籍情報更新'),
              onPressed: () async {
                processingStatusNotifier.state = 'LLM・画像一括処理を開始します...';
                final result = await kindleDataNotifier.processBooksWithLlm(
                  updateLlmInfo: _updateLlmInfo,
                  updateImage: _updateImage,
                  onProgress: (progress) {
                    ref.read(llmProcessingProgressProvider.notifier).state = progress;
                  },
                );
                processingStatusNotifier.state = result;
                ref.invalidate(uniqueGenresProvider); // ジャンルリストを更新
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
              },
            ),
            // ★追加: 一括処理中のみ停止ボタンを表示
            if (overallStatus.contains('LLM') && llmProgress.isNotEmpty)
              ElevatedButton.icon(
                icon: const Icon(Icons.stop, color: Colors.white),
                label: const Text('停止', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  kindleDataNotifier.cancelProcessing();
                },
              ),
            const SizedBox(height: 8),
            // LLM処理の進捗表示エリア
            if (llmProgress.isNotEmpty && overallStatus.contains('LLM')) // LLM関連の処理中のみ表示
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LLM処理進捗:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(llmProgress, style: const TextStyle(color: Colors.blueGrey)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined, color: Colors.white),
              label: const Text('DB全件削除 & リストクリア', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[400],
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('確認'),
                      content: const Text('本当にデータベース内の全書籍を削除し、リストをクリアしますか？この操作は元に戻せません。'),
                      actions: <Widget>[
                        TextButton(
                          child: const Text('キャンセル'),
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                        ),
                        TextButton(
                          child: const Text('削除実行', style: TextStyle(color: Colors.red)),
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                        ),
                      ],
                    );
                  },
                );

                if (confirmed == true) {
                  await bookListNotifier.clearBooks();
                  const resultMsg = 'DB全件削除 & 書籍リストをクリアしました。';
                  processingStatusNotifier.state = resultMsg;
                  ref.invalidate(uniqueGenresProvider);
                  ref.invalidate(uniqueStatusesProvider);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(resultMsg)));
                } else {
                  const cancelMsg = 'DB全件削除はキャンセルされました。';
                  processingStatusNotifier.state = cancelMsg;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(cancelMsg)));
                }
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'APIキー設定',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _geminiApiKeyController,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key',
                hintText: 'Gemini APIキーを入力',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _googleSearchApiKeyController,
              decoration: const InputDecoration(
                labelText: 'Google Search API Key',
                hintText: 'Google Custom Search APIキーを入力',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _googleSearchEngineIdController,
              decoration: const InputDecoration(
                labelText: 'Google Search Engine ID',
                hintText: 'Google Programmable Search Engine IDを入力',
                border: OutlineInputBorder(),
              ),
              obscureText: false, // Engine IDは通常隠す必要なし
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('APIキーを保存'),
              onPressed: _saveApiKeys,
            ),
            const SizedBox(height: 24),
            const Divider(),
            // TODO: アプリバージョン情報やその他の設定項目をここに追加可能
          ],
        ),
      ),
    );
  }
} 