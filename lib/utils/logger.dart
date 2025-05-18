import 'dart:core'; // DateTimeのために必要

// タイムスタンプ付きでログを出力する関数
void printWithTimestamp(String message) {
  final now = DateTime.now();
  // 標準のprint関数を使用。IDEや実行環境によっては、この出力もリダイレクトや加工が可能。
  print('$now: $message');
} 