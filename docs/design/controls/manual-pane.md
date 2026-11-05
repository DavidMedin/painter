# Discoverable Controls and the Docked Manual Pane

Design for labeled controls, hover hints, contextual F1 help, the docked Manual pane, and touch-target sizing. Observable behavior is in [behavior](behavior.md). The pane host is [pane-system](../panes/pane-system.md). Notation: [EARS+](../README.md#requirement-notation-ears).

## Status

Accepted and implemented. Combines the former ADR 0008 (controls and touch targets) and ADR 0013 (Manual pane). The workspace selector of ADR 0008 was superseded by the [pane system](../panes/pane-system.md).

## Context

The UX requirements call for labeled, icon-bearing buttons with concise hover hints and pressed feedback, contextual help reachable from any interactive control using F1, and configurable targets for touch use. Help content needs a stable mapping from controls to articles, and opening an article should keep the painting workspace visible rather than replace it with a modal surface. The pane system already provides split panes shared by Canvas, Diagnostics, and Settings.

## Decision

### Controls

- **PNT-A0008-04** The shared controls shall provide labeled actions (`lib/ui/painter_action_button.dart`), leading icons, concise tooltips, pressed-state feedback, and help topics.
- **PNT-ARC-054** The `lib/help/contextual_help.dart` shall catalog hover hints and F1 articles.

### Help catalog

- **PNT-A0013-01** Each control shall have a typed `HelpId`.
- **PNT-A0013-02** The `ManualCatalog` shall keep tooltip text, article text, and navigation sections together, and controls shall refer to IDs rather than duplicate help text.

### F1 precedence

- **PNT-A0008-05** WHEN the user presses F1 over a hovered control, the Help System shall open that control's article.
- **PNT-A0008-06** IF no control is hovered and a control has keyboard focus, THEN the Help System shall open the focused control's article.
- **PNT-A0008-07** IF no control is hovered or focused, THEN the Help System shall open general help.

### Manual pane

- **PNT-A0013-03** The Pane System shall provide Manual as a pane kind.
- **PNT-A0013-04** The `ManualPane` shall present the catalog's expandable navigation tree on the left and the selected article on the right.
- **PNT-A0013-05** The Pane System shall store the article selection on the pane descriptor.
- **PNT-A0013-09** WHEN help opens and a Manual pane exists, the Help System shall navigate and focus that pane.
- **PNT-A0013-10** WHEN help opens and no Manual pane exists, the Pane System shall split the pane with the greatest width and open the article there.
- **PNT-A0013-11** WHEN the user selects an article in the navigation tree, the `ManualPane` shall update the selected article.
- **PNT-A0013-12** The Manual pane shall participate in the existing split, resize, selector, and close behavior.

### Touch targets

- **PNT-A0008-08** The touch-size switch shall be an app-wide setting.
- **PNT-A0008-09** WHILE the touch-size setting is standard, every target shall be at least 48 logical pixels high.
- **PNT-A0008-10** WHILE the touch-size setting is enlarged, every target shall be at least 56 logical pixels high.
- **PNT-A0008-11** WHEN the app starts, the touch-size setting shall default to standard.
- **PNT-A0008-12** The Painter shall hold the touch-size choice for the current app session.
- **PNT-ARC-056** The `TouchTargetSettings` (in `lib/ui/touch_target_settings.dart`) shall provide the app-wide minimum control height of 48 logical pixels for standard targets and 56 logical pixels for enlarged targets.

Retired requirement IDs for this document are recorded in the [retired ID registry](../README.md#retired-requirement-ids).

## Consequences

- One shared size setting keeps the app bar, picker, pane controls, and help dialog aligned when the user enlarges targets.
- Adding a help target requires a `HelpId` and a matching catalog entry. Catalog completeness is covered by a test.
- Manual navigation and Log record controls use catalog-backed `HelpTarget`s;
  hover and keyboard focus both select their help topic. Adding a target
  requires a typed `HelpId`, matching tooltip and article, and coverage for the
  pointer and focus paths.
- Help descriptions and tooltips must be updated when their controls' behavior changes.
- Only one Manual pane is created by F1. Repeated F1 requests reuse that pane and change its selected article.
- The Manual pane consumes width from the widest existing pane when first opened. There is no floating or modal help window.
- Manual navigation and pane selectors/menus/dropdowns use the shared target
  height policy; enlarged mode gives these targets a minimum height of 56
  logical pixels.
- The target sizes are implementation choices, not artist-tested production accessibility measurements.
- Headless tests cover F1 selection and reuse, tree navigation, widest-pane splitting, and help opened from a file-error dialog. The Release app builds.
- Not verified: the Manual pane's appearance in a running macOS window.
