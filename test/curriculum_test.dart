import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_ai_chat/agent/context_assembler.dart';
import 'package:offline_ai_chat/agent/context_budget.dart';
import 'package:offline_ai_chat/agent/curriculum/textbook_retriever.dart';
import 'package:offline_ai_chat/agent/memory/session_memory.dart';
import 'package:offline_ai_chat/curriculum/curriculum_index.dart';
import 'package:offline_ai_chat/curriculum/curriculum_pack.dart';
import 'package:offline_ai_chat/curriculum/curriculum_service.dart';
import 'package:offline_ai_chat/domain/generation_configuration.dart';
import 'package:offline_ai_chat/l10n/app_strings_bn.dart';
import 'package:offline_ai_chat/l10n/app_strings_en.dart';
import 'package:offline_ai_chat/model_management/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Writes a pack in the exact schema `scripts/curriculum/nctb_pipeline.py` produces.
Future<String> _writePack(Directory directory, String name) async {
  final path = '${directory.path}/$name';
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
      'file_key TEXT NOT NULL, page_count INTEGER, source_url TEXT)');
  await db.execute('CREATE TABLE chunks (id INTEGER PRIMARY KEY, book_id TEXT NOT NULL, '
      'chapter TEXT, page_start INTEGER, page_end INTEGER, text TEXT NOT NULL, embedding BLOB)');
  await db.insert('meta', {'key': 'pack_id', 'value': 'general_class-7_bn'});
  await db.insert('books', {'id': 'sci', 'title': 'বিজ্ঞান', 'file_key': 'sci'});
  await db.insert('books', {'id': 'eng', 'title': 'English For Today', 'file_key': 'eng'});
  const passages = [
    // `য়` is written decomposed (U+09AF U+09BC), as Python's NFC leaves it in real packs.
    ('sci', 12, 'সালোকসংশ্লেষণ একটি জৈব রাসায়নিক প্রক্রিয়া। এই প্রক্রিয়ায় সবুজ উদ্ভিদ সূর্যের আলো ব্যবহার করে শর্করা তৈরি করে।'),
    ('sci', 30, 'পানির প্রধান উৎসগুলো হলো পুকুর, নদী, খাল ও বিল। বৃষ্টির পানিও একটি উৎস।'),
    ('sci', 31, 'কী কী খাবার খেলে শরীর সুস্থ থাকে তা আমরা এই অধ্যায়ে জানব।'),
    ('eng', 75, 'A noun is the name of a person, place or thing. Noun, pronoun and verb are parts of speech.'),
  ];
  for (final (book, page, text) in passages) {
    await db.insert('chunks', {'book_id': book, 'page_start': page, 'page_end': page, 'text': text});
  }
  await db.close();
  return path;
}

void main() {
  sqfliteFfiInit();
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('curriculum'));
  tearDown(() => directory.deleteSync(recursive: true));

  group('CurriculumIndex', () {
    test('finds a Bangla passage from an inflected word and either keyboard spelling', () async {
      final index = await CurriculumIndex.open(
        await _writePack(directory, 'pack.db'),
        factory: databaseFactoryFfi,
      );
      addTearDown(index.close);

      // "-এর" ending in the question, bare word in the book; precomposed `য়` in the question.
      final results = await index.search('সালোকসংশ্লেষণের প্রক্রিয়া কী?');
      expect(results, isNotEmpty);
      expect(results.first.bookTitle, 'বিজ্ঞান');
      expect(results.first.page, 12);
    });

    test('does not match on question words alone', () async {
      final index = await CurriculumIndex.open(
        await _writePack(directory, 'pack.db'),
        factory: databaseFactoryFfi,
      );
      addTearDown(index.close);

      // Page 31 contains "কী কী", but nothing about the moon.
      expect(await index.search('চাঁদ কী?'), isEmpty);
    });

    test('searches English passages too', () async {
      final index = await CurriculumIndex.open(
        await _writePack(directory, 'pack.db'),
        factory: databaseFactoryFfi,
      );
      addTearDown(index.close);

      final results = await index.search('What is a noun?');
      expect(results.single.bookTitle, 'English For Today');
    });

    test('scores a matchinfo blob that is not 4-byte aligned, as Android delivers it', () {
      // p=1 phrase, c=1 column, n=10 rows, a=[20], l=[20], x=[2 hits here, 5 total, 3 rows].
      final aligned = Uint8List.view(
          Uint32List.fromList([1, 1, 10, 20, 20, 2, 5, 3]).buffer);
      // The same bytes, one byte into a larger buffer: a Uint32List view of this throws.
      final padded = Uint8List(aligned.length + 1)..setRange(1, aligned.length + 1, aligned);
      final misaligned = Uint8List.sublistView(padded, 1);
      expect(misaligned.offsetInBytes % 4, isNot(0));
      final expected = CurriculumIndex.bm25FromMatchInfo(aligned);
      expect(expected, greaterThan(0));
      expect(CurriculumIndex.bm25FromMatchInfo(misaligned), expected);
    });

    test('builds the full-text index once, not on every open', () async {
      final path = await _writePack(directory, 'pack.db');
      await (await CurriculumIndex.open(path, factory: databaseFactoryFfi)).close();
      final db = await databaseFactoryFfi.openDatabase(path);
      final version = await db.rawQuery("SELECT value FROM meta WHERE key = 'app_fts_version'");
      await db.close();
      expect(version.single['value'], '1');
    });
  });

  test('CurriculumService: manifest → download → index → active → search', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final packSource = Directory.systemTemp.createTempSync('source');
    addTearDown(() => packSource.deleteSync(recursive: true));
    final packBytes = await File(await _writePack(packSource, 'general_class-7_bn.db')).readAsBytes();

    final manifest = {
      'academic_year': 2026,
      'packs': [
        {
          'id': 'general_class-7_bn',
          'file': 'general_class-7_bn.db',
          'stream': 'general',
          'class': 'class-7',
          'version': 'bn',
          'books': 2,
          'chunks': 4,
          'size_bytes': packBytes.length,
        },
      ],
    };
    final client = MockClient((request) async {
      if (request.url.path.endsWith('manifest.json')) {
        return http.Response.bytes(utf8.encode(jsonEncode(manifest)), 200);
      }
      if (request.url.path.endsWith('general_class-7_bn.db')) {
        return http.Response.bytes(packBytes, 200);
      }
      return http.Response('', 404);
    });

    final service = CurriculumService(
      directory: directory,
      settings: settings,
      httpClient: client,
      databaseFactory: databaseFactoryFfi,
    );
    addTearDown(service.dispose);
    await service.start();
    await service.refreshManifest();

    final pack = service.manifest!.packs.single;
    expect(service.statusOf(pack), CurriculumPackStatus.notInstalled);
    expect(await service.search('পানির উৎস'), isEmpty); // nothing installed yet

    await service.download(pack);
    expect(service.errorMessage, isNull);
    expect(service.statusOf(pack), CurriculumPackStatus.installed);
    // The first download becomes the active pack without a second tap.
    expect(settings.activeCurriculumPackId, 'general_class-7_bn');

    final results = await service.search('পানির উৎস কী কী?');
    expect(results.first.page, 30);

    await service.delete(pack);
    expect(settings.activeCurriculumPackId, isNull);
    expect(await service.search('পানির উৎস'), isEmpty);
  });

  test('textbook passages reach the system prompt with citations and tutoring instructions', () {
    final assembled = const ContextAssembler().assemble(
      ContextAssemblerInput(
        baseConfiguration: GenerationConfiguration.standard(gpuLayers: 0),
        memory: const SessionMemory(),
        documentChunks: const [],
        webChunks: const [],
        documentSearchPerformed: false,
        webSearchPerformed: false,
        textbookExcerpts: const [
          TextbookExcerpt(bookTitle: 'বিজ্ঞান', page: 12, text: 'সালোকসংশ্লেষণ একটি প্রক্রিয়া।'),
        ],
        textbookSearchPerformed: true,
      ),
      budget: ContextBudget.standard(allocatedContextLength: 4096),
    );
    expect(assembled.systemPrompt, contains('<textbook_sources>'));
    expect(assembled.systemPrompt, contains('[book:1] (বিজ্ঞান, page 12)'));
    expect(assembled.systemPrompt, contains('TEXTBOOK_SEARCH_PERFORMED=true'));
  });

  test('pack titles read naturally in both languages', () {
    expect(
      const AppStringsEn().packTitle([9, 10], 'general', banglaVersion: true),
      'Class 9–10 · Bangla version',
    );
    expect(
      const AppStringsBn().packTitle([9, 10], 'general', banglaVersion: true),
      'নবম–দশম শ্রেণি · বাংলা ভার্সন',
    );
    expect(const AppStringsBn().packDetails(33, '77 MB'), '৩৩টি বই · 77 MB');
  });

  test('the manifest sorts packs by class, Bangla version first', () {
    final manifest = CurriculumManifest.fromJson({
      'packs': [
        for (final id in ['general_class-9-10_en', 'general_class-3_bn', 'general_class-9-10_bn'])
          {
            'id': id,
            'file': '$id.db',
            'stream': 'general',
            'class': id.split('_')[1],
            'version': id.split('_')[2],
          },
      ],
    });
    expect(manifest.packs.map((pack) => pack.id), [
      'general_class-3_bn',
      'general_class-9-10_bn',
      'general_class-9-10_en',
    ]);
  });
}
