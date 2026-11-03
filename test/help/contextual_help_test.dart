// What: Verifies contextual help precedence used by the app's F1 command.
// Why: F1 must show the hovered control's article, then keyboard focus, then
//   general help when no control is active.
// Covers: lib/help/contextual_help.dart (HelpState and HelpTopics).

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/contextual_help.dart';

void main() {
  test('hovered help takes precedence over focus and general help', () {
    final state = HelpState();
    expect(state.activeTopic, HelpTopics.general);

    state.setFocused(HelpTopics.openDocument);
    expect(state.activeTopic, HelpTopics.openDocument);

    state.setHovered(HelpTopics.workspace);
    expect(state.activeTopic, HelpTopics.workspace);

    state.setHovered(null);
    expect(state.activeTopic, HelpTopics.openDocument);

    state.setFocused(null);
    expect(state.activeTopic, HelpTopics.general);
    state.dispose();
  });
}
