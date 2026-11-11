// What: SessionRoster and SessionMember: the Participants as the UI shows
//   them, each with whether it is present, and the Host computed by the rule
//   of docs/decisions/013-session-networking.md PNT-A0019-07.
// Why: the Host depends on presence, which only the network knows, and on
//   the session document, which every peer shares; a pure function of both
//   lets the network and tests compute it identically. See the Session
//   overview in session_network.dart.
// Coupled to: session_document.dart (SessionParticipant), session_network.dart
//   (computes a roster on every presence or document change and repairs
//   `host` from it).

import 'package:flutter/foundation.dart' show listEquals;

import 'session_document.dart';

/// One Participant of a [SessionRoster].
final class SessionMember {
  const SessionMember({required this.participant, required this.present});

  final SessionParticipant participant;

  /// Whether the local peer has a live connection to it, or it is the local
  /// Participant (PNT-A0019-07).
  final bool present;

  @override
  bool operator ==(Object other) =>
      other is SessionMember &&
      other.participant == participant &&
      other.present == present;

  @override
  int get hashCode => Object.hash(participant, present);
}

/// The Participants of a Session in join order, and the Host.
final class SessionRoster {
  const SessionRoster({required this.members, required this.hostId});

  /// The roster of [participants] given who is [present] and the document's
  /// [hostField]. The Host is [hostField] if present, else the present
  /// Participant with the smallest `joined`, ties broken by id
  /// (PNT-A0019-07); null when no Participant is present.
  factory SessionRoster.compute({
    required List<SessionParticipant> participants,
    required String? hostField,
    required Set<String> present,
  }) {
    final ordered = List.of(participants)..sort(_byJoinOrder);
    String? hostId;
    if (hostField != null &&
        present.contains(hostField) &&
        ordered.any((participant) => participant.id == hostField)) {
      hostId = hostField;
    } else {
      for (final participant in ordered) {
        if (present.contains(participant.id)) {
          hostId = participant.id;
          break;
        }
      }
    }
    return SessionRoster(
      members: List.unmodifiable([
        for (final participant in ordered)
          SessionMember(
            participant: participant,
            present: present.contains(participant.id),
          ),
      ]),
      hostId: hostId,
    );
  }

  /// No Participants: before a Session exists in the document.
  static const SessionRoster empty = SessionRoster(members: [], hostId: null);

  /// Every well-formed participant entry, including absent and left ones,
  /// ordered by `joined` then id.
  final List<SessionMember> members;

  /// The Host's participant id.
  final String? hostId;

  /// The member with [id], or null.
  SessionMember? member(String id) {
    for (final member in members) {
      if (member.participant.id == id) return member;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SessionRoster &&
      other.hostId == hostId &&
      listEquals(other.members, members);

  @override
  int get hashCode => Object.hash(hostId, Object.hashAll(members));

  static int _byJoinOrder(SessionParticipant a, SessionParticipant b) {
    final byJoined = a.joined.compareTo(b.joined);
    return byJoined != 0 ? byJoined : a.id.compareTo(b.id);
  }
}
