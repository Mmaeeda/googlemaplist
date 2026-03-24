import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/csv/tag_csv_service.dart';
import 'core_providers.dart';

final tagCsvServiceProvider = Provider<TagCsvService>((ref) => TagCsvService());

class TagCsvExportNotifier extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  Future<String?> export() async {
    state = const AsyncLoading();
    try {
      final csv = await ref.read(tagCsvServiceProvider).exportCsv(
            placeRepository: ref.read(placeRepositoryProvider),
            placeGroupRepository: ref.read(placeGroupRepositoryProvider),
            groupRepository: ref.read(groupRepositoryProvider),
          );
      state = AsyncData(csv);
      return csv;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final tagCsvExportProvider =
    NotifierProvider<TagCsvExportNotifier, AsyncValue<String?>>(
  TagCsvExportNotifier.new,
);

class TagCsvImportNotifier extends Notifier<AsyncValue<TagCsvImportResult?>> {
  @override
  AsyncValue<TagCsvImportResult?> build() => const AsyncData(null);

  Future<TagCsvImportResult?> import(String csvContent) async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(tagCsvServiceProvider).importCsv(
            csvContent: csvContent,
            placeRepository: ref.read(placeRepositoryProvider),
            placeGroupRepository: ref.read(placeGroupRepositoryProvider),
            groupRepository: ref.read(groupRepositoryProvider),
          );
      state = AsyncData(result);
      return result;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final tagCsvImportProvider =
    NotifierProvider<TagCsvImportNotifier, AsyncValue<TagCsvImportResult?>>(
  TagCsvImportNotifier.new,
);
