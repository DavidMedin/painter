# Docked Manual pane

## Status

Accepted and implemented.

## Context

Painter's controls already expose hover hints and contextual F1 help. Help
content needs a stable mapping from controls to articles, and opening an article
should keep the painting workspace visible rather than replacing it with a
modal surface. The existing pane system provides horizontal split panes shared
by Canvas, Diagnostics, and Settings.

## Decision

- Assign controls typed `HelpId` values. Keep tooltip text, article text, and
  navigation sections together in `ManualCatalog`; controls refer to IDs rather
  than duplicating help text.
- Add Manual as a pane kind. `ManualPane` presents the catalog's expandable
  navigation tree on the left and the selected article on the right. Article
  selection is stored on the pane descriptor.
- Preserve F1 precedence: hovered control, then keyboard-focused control, then
  general help. Opening help navigates and focuses an existing Manual pane.
  Otherwise, split the pane with the greatest width and open the article there.
- Tree navigation updates the selected article in that Manual pane. The pane
  participates in the existing split, resize, selector, and close behavior.

## Consequences

- Adding a help target requires a `HelpId` and a matching catalog entry; catalog
  completeness is covered by a test.
- Only one Manual pane is created by F1. Repeated F1 requests reuse that pane
  and change its selected article.
- The Manual pane consumes width from the widest existing pane when first
  opened; there is no separate floating or modal help window.
- Headless tests cover F1 selection and reuse, tree navigation, widest-pane
  splitting, and help opened from a file-error dialog. The macOS Release app
  builds, but no GUI window was opened and the Manual's appearance is not
  visually verified. See the [Manual and Binary Split-Tree Integration
  Verification](../status.md#manual-and-binary-split-tree-integration-verification).
