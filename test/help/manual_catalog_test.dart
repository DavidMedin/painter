// What: Verifies the centralized manual maps every help id to one article and
//   one navigation-tree entry.
// Why: F1 controls must never point at missing or unreachable manual text.
// Covers: lib/help/manual_catalog.dart (HelpId, ManualCatalog, and sections).

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/manual_catalog.dart';

void main() {
  test('every help id has one article and one navigation entry', () {
    final ids = HelpId.values.toSet();
    final navigationIds = ManualCatalog.sections
        .expand((section) => section.articles)
        .toList();

    expect(ManualCatalog.articles.keys.toSet(), ids);
    expect(navigationIds.toSet(), ids);
    expect(navigationIds, hasLength(ids.length));

    for (final id in HelpId.values) {
      final article = ManualCatalog.article(id);
      expect(article.id, id);
      expect(article.title, isNotEmpty);
      expect(article.content, isNotEmpty);
      expect(
        ManualCatalog.sections.any(
          (section) =>
              section.title == article.section && section.articles.contains(id),
        ),
        isTrue,
      );
    }
  });
}
