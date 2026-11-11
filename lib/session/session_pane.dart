// What: SessionPane, the content of a pane in Session mode, and the dialogs
//   of the Session flows: the name dialog of Start session, the address and
//   name dialog of Join session, the refusal dialog naming both Engine
//   versions, and the failure dialog.
// Why: docs/spec/multiplayer.md asks the system to show the Participants and
//   the Host (MPLY-9), the Session addresses (MPLY-2), to ask for a name
//   (MPLY-10) and to show a refused join's Engine versions (MPLY-8); the
//   workspace controls are WKSP-32 and WKSP-36. The widgets only show state
//   and report choices: ../main.dart owns the documents and the network and
//   runs every flow, so the pane holds no Session state of its own.
// Coupled to: session_network.dart (SessionNetwork.roster, addresses,
//   localId, SessionJoinRefused), session_roster.dart (SessionRoster),
//   session_protocol.dart (RefuseReason), ../main.dart (callbacks, the
//   flows behind them), ../help/manual_catalog.dart (one article per
//   control), ../ui/painter_action_button.dart. See the Session overview in
//   session_network.dart.

import 'package:flutter/material.dart';

import '../help/contextual_help.dart';
import '../ui/painter_action_button.dart';
import '../ui/touch_target.dart';
import 'session_network.dart';
import 'session_protocol.dart';
import 'session_roster.dart';

/// What the user entered in the Join session dialog.
typedef SessionJoinRequest = ({String address, String name});

/// The Session pane. Outside a Session ([network] null or not active) it
/// offers Start session and Join session; inside it lists the Session
/// addresses and every Participant still in the Session, with the
/// workspace and Host actions, and offers Leave session.
///
/// It rebuilds from [SessionNetwork.roster], which changes with presence
/// and with every session document change, so names, the Host and
/// workspace membership stay current.
class SessionPane extends StatelessWidget {
  const SessionPane({
    super.key,
    required this.network,
    required this.busy,
    required this.onStart,
    required this.onJoin,
    required this.onLeave,
    required this.onJoinWorkspace,
    required this.onLeaveWorkspace,
    required this.onPromote,
  });

  /// The local Participant's network while the app is in a Session.
  final SessionNetwork? network;

  /// Whether a Session flow is running; every action is disabled meanwhile.
  final bool busy;

  final VoidCallback onStart;
  final VoidCallback onJoin;
  final VoidCallback onLeave;

  /// Called with the participant id whose workspace to join (WKSP-32).
  final ValueChanged<String> onJoinWorkspace;

  /// Leaves the joined workspace (WKSP-36).
  final VoidCallback onLeaveWorkspace;

  /// Called with the participant id to make Host (MPLY-11).
  final ValueChanged<String> onPromote;

  @override
  Widget build(BuildContext context) {
    final network = this.network;
    if (network == null || !network.isActive) return _outside(context);
    return ValueListenableBuilder<SessionRoster>(
      valueListenable: network.roster,
      builder: (context, roster, _) => _inside(context, network, roster),
    );
  }

  Widget _outside(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'You are not in a session.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PainterActionButton(
            key: const ValueKey('session-start'),
            icon: Icons.play_arrow,
            label: 'Start session',
            topic: HelpIds.startSession,
            onPressed: busy ? null : onStart,
          ),
          PainterActionButton(
            key: const ValueKey('session-join'),
            icon: Icons.login,
            label: 'Join session',
            topic: HelpIds.joinSession,
            onPressed: busy ? null : onJoin,
          ),
        ],
      ),
    ],
  );

  Widget _inside(
    BuildContext context,
    SessionNetwork network,
    SessionRoster roster,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final localId = network.localId;
    final local = roster.member(localId)?.participant;
    final isHost = roster.hostId == localId;
    final addresses = network.addresses;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Your session addresses', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        if (addresses.isEmpty)
          const Text('No network address was found.')
        else
          for (var i = 0; i < addresses.length; i++)
            HelpTarget(
              topic: HelpIds.sessionAddresses,
              child: SelectableText(
                addresses[i],
                key: ValueKey('session-address-$i'),
              ),
            ),
        const SizedBox(height: 16),
        Text('Participants', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final member in roster.members)
          if (!member.participant.left)
            _participantRow(
              member,
              isLocal: member.participant.id == localId,
              isHost: member.participant.id == roster.hostId,
              localIsHost: isHost,
              localWorkspace: local?.workspace,
            ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (local?.previousWorkspace != null)
              PainterActionButton(
                key: const ValueKey('session-leave-workspace'),
                icon: Icons.logout,
                label: 'Leave workspace',
                topic: HelpIds.leaveWorkspace,
                onPressed: busy ? null : onLeaveWorkspace,
              ),
            PainterActionButton(
              key: const ValueKey('session-leave'),
              icon: Icons.exit_to_app,
              label: 'Leave session',
              topic: HelpIds.leaveSession,
              onPressed: busy ? null : onLeave,
            ),
          ],
        ),
      ],
    );
  }

  /// One Participant: its name with the markers MPLY-9 asks for, then
  /// 'Join workspace' unless it is local or already shares the local
  /// workspace, and 'Make host' while the local Participant is Host and it
  /// is present (SessionNetwork.promote requires presence).
  Widget _participantRow(
    SessionMember member, {
    required bool isLocal,
    required bool isHost,
    required bool localIsHost,
    required String? localWorkspace,
  }) {
    final participant = member.participant;
    final id = participant.id;
    final label = [
      participant.name.isEmpty ? '(no name)' : participant.name,
      if (isLocal) '(you)',
      if (isHost) '· Host',
      if (!member.present) '· away',
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HelpTarget(
            topic: HelpIds.sessionParticipant,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: touchTargetHeight),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isHost ? Icons.star : Icons.person_outline, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      key: ValueKey('session-participant-$id'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isLocal && participant.workspace != localWorkspace)
            PainterActionButton(
              key: ValueKey('session-join-workspace-$id'),
              icon: Icons.group_add_outlined,
              label: 'Join workspace',
              topic: HelpIds.joinWorkspace,
              onPressed: busy ? null : () => onJoinWorkspace(id),
            ),
          if (!isLocal && localIsHost && member.present)
            PainterActionButton(
              key: ValueKey('session-make-host-$id'),
              icon: Icons.star_outline,
              label: 'Make host',
              topic: HelpIds.makeHost,
              onPressed: busy ? null : () => onPromote(id),
            ),
        ],
      ),
    );
  }
}

/// Asks for the name to show the other Participants when starting a
/// Session (MPLY-10), offering [initialName], the account name. Returns the
/// trimmed name, or null when cancelled.
Future<String?> showStartSessionDialog(
  BuildContext context, {
  required String initialName,
}) async {
  final values = await showDialog<List<String>>(
    context: context,
    builder: (context) => _SessionFormDialog(
      title: 'Start session',
      confirmLabel: 'Start',
      confirmIcon: Icons.play_arrow,
      confirmTopic: HelpIds.startSession,
      fields: [
        _FormField(
          key: 'session-name-field',
          label: 'Your name',
          topic: HelpIds.sessionName,
          initial: initialName,
        ),
      ],
    ),
  );
  return values?.single;
}

/// Asks for the Session address to join (MPLY-3) and the name to show
/// (MPLY-10), offering [initialName]. Returns both trimmed, or null when
/// cancelled.
Future<SessionJoinRequest?> showJoinSessionDialog(
  BuildContext context, {
  required String initialName,
}) async {
  final values = await showDialog<List<String>>(
    context: context,
    builder: (context) => _SessionFormDialog(
      title: 'Join session',
      confirmLabel: 'Join',
      confirmIcon: Icons.login,
      confirmTopic: HelpIds.joinSession,
      fields: [
        const _FormField(
          key: 'session-address-field',
          label: 'Session address (host:port)',
          topic: HelpIds.sessionAddress,
          initial: '',
        ),
        _FormField(
          key: 'session-name-field',
          label: 'Your name',
          topic: HelpIds.sessionName,
          initial: initialName,
        ),
      ],
    ),
  );
  if (values == null) return null;
  return (address: values[0], name: values[1]);
}

/// Shows that the Session refused the join, why, and both Engine versions
/// (MPLY-8).
Future<void> showSessionRefusedDialog(
  BuildContext context,
  SessionJoinRefused refusal,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('session-refused-dialog'),
    title: const Text('Join refused'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (refusal.reason) {
          RefuseReason.engine =>
            'The session draws strokes with another Engine version.',
          RefuseReason.protocol =>
            'The session uses another version of the network protocol.',
          _ => 'The session refused the join (${refusal.reason}).',
        }),
        const SizedBox(height: 8),
        Text('Your Engine version: ${refusal.localEngine}'),
        Text('Session Engine version: ${refusal.sessionEngine}'),
      ],
    ),
    actions: [_closeButton(context)],
  ),
);

/// Shows that a Session [operation] (for example 'join the session') failed
/// with [error]; nothing changed.
Future<void> showSessionErrorDialog(
  BuildContext context,
  String operation,
  Object error,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('session-error-dialog'),
    title: const Text('Session operation failed'),
    content: Text('Could not $operation: $error'),
    actions: [_closeButton(context)],
  ),
);

Widget _closeButton(BuildContext context) => PainterActionButton(
  key: const ValueKey('session-dialog-close'),
  icon: Icons.close,
  label: 'Close',
  topic: HelpIds.dialogClose,
  onPressed: () => Navigator.of(context).pop(),
);

/// One text field of a [_SessionFormDialog].
final class _FormField {
  const _FormField({
    required this.key,
    required this.label,
    required this.topic,
    required this.initial,
  });

  /// The field's widget key, for tests and the integration test.
  final String key;
  final String label;
  final HelpId topic;
  final String initial;
}

/// A dialog of required text fields; it pops their trimmed values in order,
/// and its confirm button is enabled only while none is empty.
class _SessionFormDialog extends StatefulWidget {
  const _SessionFormDialog({
    required this.title,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.confirmTopic,
    required this.fields,
  });

  final String title;
  final String confirmLabel;
  final IconData confirmIcon;
  final HelpId confirmTopic;
  final List<_FormField> fields;

  @override
  State<_SessionFormDialog> createState() => _SessionFormDialogState();
}

class _SessionFormDialogState extends State<_SessionFormDialog> {
  late final List<TextEditingController> _controllers = [
    for (final field in widget.fields)
      TextEditingController(text: field.initial)..addListener(_changed),
  ];

  List<String> get _values => [
    for (final controller in _controllers) controller.text.trim(),
  ];

  bool get _complete => _values.every((value) => value.isNotEmpty);

  void _changed() => setState(() {});

  void _confirm() {
    if (_complete) Navigator.of(context).pop(_values);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.fields.length; i++)
            HelpTarget(
              topic: widget.fields[i].topic,
              child: TextField(
                key: ValueKey(widget.fields[i].key),
                controller: _controllers[i],
                autofocus: i == 0,
                decoration: InputDecoration(labelText: widget.fields[i].label),
                onSubmitted: (_) => _confirm(),
              ),
            ),
        ],
      ),
    ),
    actions: [
      PainterActionButton(
        key: const ValueKey('session-dialog-cancel'),
        icon: Icons.close,
        label: 'Cancel',
        topic: HelpIds.dialogCancel,
        onPressed: () => Navigator.of(context).pop(),
      ),
      PainterActionButton(
        key: const ValueKey('session-dialog-confirm'),
        icon: widget.confirmIcon,
        label: widget.confirmLabel,
        topic: widget.confirmTopic,
        onPressed: _complete ? _confirm : null,
      ),
    ],
  );
}
