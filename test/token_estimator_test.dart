import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/agent/token_estimator.dart';

void main() {
  group('TokenEstimator.estimateTokenCount', () {
    test('approximates four characters per token', () {
      expect(TokenEstimator.estimateTokenCount('a' * 400), 100);
    });

    test('never returns zero for non-empty text', () {
      expect(TokenEstimator.estimateTokenCount('hi'), 1);
    });

    test('returns at least one for the empty string', () {
      // `0 ~/ 4 == 0`, and the guard lifts it to 1 — callers divide by this.
      expect(TokenEstimator.estimateTokenCount(''), 1);
    });
  });

  group('TokenEstimator.truncate', () {
    test('leaves text inside the budget untouched', () {
      const text = 'short enough';
      expect(TokenEstimator.truncate(text, tokenBudget: 100), text);
    });

    test('appends an ellipsis when it cuts', () {
      final result = TokenEstimator.truncate('a' * 400, tokenBudget: 10);
      expect(result.length, 41);
      expect(result.endsWith('…'), isTrue);
    });

    test('returns empty for a non-positive budget', () {
      expect(TokenEstimator.truncate('anything', tokenBudget: 0), '');
      expect(TokenEstimator.truncate('anything', tokenBudget: -5), '');
    });
  });
}
