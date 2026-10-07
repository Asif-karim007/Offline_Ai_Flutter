import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:offline_ai_chat/agent/agent_request.dart';
import 'package:offline_ai_chat/agent/agent_router.dart';
import 'package:offline_ai_chat/agent/device_context_tool.dart';
import 'package:offline_ai_chat/agent/internal_term_scrubber.dart';
import 'package:offline_ai_chat/agent/retrieval/bm25_scorer.dart';
import 'package:offline_ai_chat/l10n/app_strings.dart';
import 'package:offline_ai_chat/l10n/app_strings_bn.dart';
import 'package:offline_ai_chat/l10n/app_strings_en.dart';
import 'package:offline_ai_chat/utilities/bangla_text.dart';

AgentRoute _route(String message) => const AgentRouter().route(AgentRequest(
      userMessage: message,
      conversationId: null,
      recentMessages: const [],
      attachedDocuments: const [],
      permissions: AgentPermissions.offlineOnly,
    ));

bool _isDeviceContext(AgentRoute route) =>
    route is DefiniteRoute && route.decision.reason == 'router_device_context';

void main() {
  // `য়` precomposed (U+09DF) and as `য` + nukta (U+09AF U+09BC): two keyboards, one word.
  const kotaPrecomposed = 'কয়টা বাজে?';
  const kotaDecomposed = 'কয়টা বাজে?';

  group('BanglaText.normalize', () {
    test('maps both spellings of য় to the same NFC form', () {
      expect(BanglaText.normalize(kotaPrecomposed), BanglaText.normalize(kotaDecomposed));
      expect(BanglaText.normalize('য়'), 'য়');
    });

    test('composes the split vowel signs ো and ৌ', () {
      expect(BanglaText.normalize('কো'), 'কো');
      expect(BanglaText.normalize('কৌ'), 'কৌ');
    });

    test('leaves English text untouched', () {
      const english = 'What time is it?';
      expect(identical(BanglaText.normalize(english), english), isTrue);
    });
  });

  group('BM25 on Bangla', () {
    test('matches a whole Bangla word instead of single letters', () {
      final scores = BM25Scorer.scores(
        query: 'সালোকসংশ্লেষণ কী',
        documents: const [
          'সালোকসংশ্লেষণ প্রক্রিয়ায় সবুজ উদ্ভিদ শর্করা তৈরি করে।',
          'সংখ্যা রেখায় ধনাত্মক ও ঋণাত্মক সংখ্যা দেখানো হয়।',
        ],
      );
      expect(scores[0], greaterThan(0));
      // Before the fix, the second passage scored too: the query had been shredded into
      // fragments like "স" and "ল" that occur in almost any Bangla sentence.
      expect(scores[1], 0);
    });

    test('matches across keyboard encodings', () {
      final scores = BM25Scorer.scores(
        query: 'প্রক্রিয়া',
        documents: const ['প্রক্রিয়া'],
      );
      expect(scores.single, greaterThan(0));
    });
  });

  group('AgentRouter in Bangla', () {
    test('routes a Bangla time question to the device clock, from either keyboard', () {
      expect(_isDeviceContext(_route(kotaPrecomposed)), isTrue);
      expect(_isDeviceContext(_route(kotaDecomposed)), isTrue);
    });

    test('routes a Bangla date question to the device clock', () {
      expect(_isDeviceContext(_route('আজ কত তারিখ?')), isTrue);
    });

    test('does not mistake a physics question for a clock question', () {
      expect(_isDeviceContext(_route('বস্তুটি মাটিতে পড়তে কত সময় লাগবে?')), isFalse);
    });

    test('does not force a history question to the web', () {
      expect(_route('পলাশীর যুদ্ধে কে জিতেছিল?'), isA<FastAnswerRoute>());
    });

    test('honours a Bangla "do not use the internet" restriction', () {
      final route = _route('ইন্টারনেট ব্যবহার করো না, আজকের খবর কী?');
      expect(route, isA<DefiniteRoute>());
      expect((route as DefiniteRoute).decision.reason, 'router_explicit_no_web');
    });

    test('sends an explicit Bangla web request to web search', () {
      final route = _route('ওয়েবে খুঁজে দেখো ঢাকার আবহাওয়া');
      expect((route as DefiniteRoute).decision.reason, 'router_explicit_web');
    });
  });

  group('replies follow the language of the question', () {
    setUpAll(() => initializeDateFormatting());

    final context = DeviceContext(
      currentDate: DateTime(2026, 10, 6, 14, 30),
      timeZoneIdentifier: '+06',
      localeName: 'en_US',
    );

    test('a Bangla date question gets a Bangla answer', () {
      final answer = DeviceContextTool.formattedAnswer('আজ কত তারিখ?', context: context);
      expect(answer, startsWith('আজ '));
      expect(answer, contains('অক্টোবর'));
    });

    test('an English date question still gets an English answer', () {
      final answer =
          DeviceContextTool.formattedAnswer("What's today's date?", context: context);
      expect(answer, startsWith('Today is '));
      expect(answer, contains('October'));
    });
  });

  group('AppStrings', () {
    test('picks the language from the locale and from the text', () {
      expect(AppStrings.forLocale(const Locale('bn', 'BD')), isA<AppStringsBn>());
      expect(AppStrings.forLocale(const Locale('fr')), isA<AppStringsEn>());
      expect(AppStrings.forText('পদার্থবিজ্ঞান কী?'), isA<AppStringsBn>());
      expect(AppStrings.forText('What is physics?'), isA<AppStringsEn>());
    });

    test('both languages offer the same number of starter suggestions', () {
      expect(const AppStringsBn().suggestions, hasLength(const AppStringsEn().suggestions.length));
    });
  });

  test('a leaked internal flag sentence is removed from a finished answer', () {
    const answer = 'নিউটনের তৃতীয় সূত্র হলো ক্রিয়া ও প্রতিক্রিয়া সমান ও বিপরীত। '
        'আমি এখানে WEB_SEARCH_PERFORMED এবং DOCUMENT_SEARCH_PERFORMED ব্যবহার করেছিলাম।';
    expect(InternalTermScrubber.scrub(answer), 'নিউটনের তৃতীয় সূত্র হলো ক্রিয়া ও প্রতিক্রিয়া সমান ও বিপরীত।');
    expect(InternalTermScrubber.scrub('A clean answer.'), 'A clean answer.');
  });
}
