// What: Tests of SessionRoster.compute (lib/session/session_roster.dart).
// Why: every peer must compute the same Host from the same document and
//   presence (docs/decisions/013-session-networking.md PNT-A0019-07,
//   MPLY-11, MPLY-12).
// Behavior verified: members are ordered by `joined` then id and flagged
//   present; the Host is `host` while present, else the present Participant
//   with the smallest `joined`, ties broken by id; no one present means no
//   Host; equal inputs give equal rosters.

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/session/session_document.dart';
import 'package:painter/session/session_roster.dart';

SessionParticipant _participant(String id, int joined) => SessionParticipant(
  id: id,
  name: id.toUpperCase(),
  joined: joined,
  workspace: 'w-$id',
  addresses: const [],
  left: false,
);

void main() {
  final participants = [
    _participant('c', 1),
    _participant('a', 0),
    _participant('b', 1),
  ];

  SessionRoster roster(String? host, Set<String> present) =>
      SessionRoster.compute(
        participants: participants,
        hostField: host,
        present: present,
      );

  test('members are in join order, ties by id, with presence', () {
    final result = roster('a', {'a', 'c'});
    expect(result.members.map((m) => m.participant.id), ['a', 'b', 'c']);
    expect(result.members.map((m) => m.present), [true, false, true]);
  });

  test('the Host is host while present', () {
    expect(roster('c', {'a', 'c'}).hostId, 'c');
  });

  test('an absent host passes to the earliest-joined present Participant', () {
    expect(roster('a', {'b', 'c'}).hostId, 'b');
    expect(roster(null, {'c'}).hostId, 'c');
    expect(roster('gone', {'a', 'b'}).hostId, 'a');
    expect(roster('a', {}).hostId, isNull);
  });

  test('equal inputs give equal rosters', () {
    expect(roster('a', {'a'}), roster('a', {'a'}));
    expect(roster('a', {'a'}), isNot(roster('a', {'a', 'b'})));
  });
}
