import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// A real answer from the on-device run (Qwen3.5-2B, question 10): Bangla prose, bold and
/// display math. It must lay out as formatted text, not as raw `$$`/`**` markup.
const _answer = r'''দেওয়া আছে যে $a + b = 7$ এবং $ab = 12$:
$$(a + b)^2 = a^2 + 2ab + b^2$$
$$49 = a^2 + b^2 + 24$$

তাই, $a^2 + b^2$ এর মান **25**।''';

void main() {
  testWidgets('a Bangla answer with LaTeX renders as math, not markup', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: GptMarkdown(_answer, useDollarSignsForLatex: true),
      )),
    ));
    expect(tester.takeException(), isNull);
    // The markup characters are consumed by the renderer rather than shown.
    expect(find.textContaining(r'$$', findRichText: true), findsNothing);
    expect(find.textContaining('**', findRichText: true), findsNothing);
  });
}
