// What: ManualPane renders the section tree and selected article from the
//   central manual catalog.
// Why: `docs/design/controls/manual-pane.md` keeps F1 help in the docked
//   workspace so users can read an article while keeping the relevant
//   application pane visible.
// Coupled to: manual_catalog.dart (ids, sections and article text),
//   pane_system.dart (selected help id and navigation callback), and
//   contextual_help.dart (control help identifiers).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/touch_target.dart';

import 'contextual_help.dart';
import 'manual_catalog.dart';

/// A browsable manual tree beside the article selected by [helpId].
class ManualPane extends StatelessWidget {
  const ManualPane({
    super.key,
    required this.helpId,
    required this.onHelpIdSelected,
  });

  final HelpId helpId;
  final ValueChanged<HelpId> onHelpIdSelected;

  @override
  Widget build(BuildContext context) {
    final article = ManualCatalog.article(helpId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final treeWidth = math.min(
          240.0,
          math.max(120.0, constraints.maxWidth * 0.36),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: treeWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: ListView(
                  key: const ValueKey('manual-navigation-tree'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final section in ManualCatalog.sections)
                      ExpansionTile(
                        key: ValueKey(
                          'manual-section-${section.title}-'
                          '${section.articles.contains(helpId)}',
                        ),
                        minTileHeight: touchTargetHeight,
                        title: HelpTarget(
                          topic: HelpIds.manualNavigation,
                          child: Text(section.title),
                        ),
                        initiallyExpanded: section.articles.contains(helpId),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding: const EdgeInsets.only(left: 8),
                        children: [
                          for (final id in section.articles)
                            HelpTarget(
                              topic: id,
                              child: ListTile(
                                key: ValueKey('manual-item-${id.name}'),
                                dense: true,
                                minTileHeight: touchTargetHeight,
                                selected: id == helpId,
                                selectedTileColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                title: Text(ManualCatalog.article(id).title),
                                onTap: () => onHelpIdSelected(id),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('manual-article'),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(article.content),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
