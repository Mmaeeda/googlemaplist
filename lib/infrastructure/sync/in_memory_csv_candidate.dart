import 'dart:typed_data';

/// A CSV candidate discovered from in-memory ZIP extraction (web).
class InMemoryCsvCandidate {
  final String fileName;
  final Uint8List bytes;
  final int score;

  const InMemoryCsvCandidate({
    required this.fileName,
    required this.bytes,
    required this.score,
  });

  @override
  String toString() =>
      'InMemoryCsvCandidate(name: $fileName, size: ${bytes.length}, score: $score)';
}
