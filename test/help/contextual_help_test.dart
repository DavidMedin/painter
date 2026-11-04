// What: Verifies contextual help precedence used by the app's F1 command.
// Why: F1 must show the hovered control's article, then keyboard focus, then
//   general help when no control is active.
// Covers: lib/help/contextual_help.dart (HelpState and HelpIds).

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/contextual_help.dart';

void main() {
  test('hovered help takes precedence over focus and general help', () {
    final state = HelpState();
    expect(state.activeTopic, HelpIds.general);

    state.setFocused(HelpIds.openDocument);
    expect(state.activeTopic, HelpIds.openDocument);

    state.setHovered(HelpIds.paneType);
    expect(state.activeTopic, HelpIds.paneType);

    state.setHovered(null);
    expect(state.activeTopic, HelpIds.openDocument);

    state.setFocused(null);
    expect(state.activeTopic, HelpIds.general);
    state.dispose();
  });
}
