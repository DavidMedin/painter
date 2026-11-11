# 013. Participants connect in a full mesh of WebSockets and run Automerge sync on each connection

Status: accepted   (supersedes: none; superseded by: none)
Date: 2026-11-11
Relates to: MPLY-1, MPLY-2, MPLY-3, MPLY-5, MPLY-8, MPLY-9, MPLY-11, MPLY-12, MPLY-15, MPLY-17, MPLY-18

## Context
The owner chose direct peer-to-peer connections by address, with no server and no NAT traversal. The Host is a title: it marks who started the Session and passes on when they leave (MPLY-11, MPLY-12), and nothing requires every peer to agree on it at every instant.

## Decision
- **PNT-A0019-01** Each Participant shall listen for WebSocket connections on TCP port 47800 on all IPv4 interfaces, or on an OS-chosen port if that one is taken, and its Session addresses are its non-loopback IPv4 addresses with that port.
- **PNT-A0019-02** Every frame shall be binary, its first byte its type: `0x01` hello, `0x02` welcome, `0x03` refuse, `0x10` sync, `0x11` sync part, `0x20` ping, `0x30` bye. Hello, welcome and refuse carry UTF-8 JSON. Sync and sync part carry one byte naming the document (0 content, 1 session) and then up to 64 KiB of an Automerge sync message: a message is sent as zero or more sync parts followed by one sync frame, and the receiver joins them, so a large message never keeps a peer silent for long.
- **PNT-A0019-03** A connecting peer shall send hello with `protocol` (1), `engine`, `participant`, `name` and `addresses`. The accepting peer shall answer refuse with `reason` and its `engine` if protocol or engine differ (MPLY-8), and welcome with its `participant` and `name` otherwise.
- **PNT-A0019-04** After welcome, both peers shall run Automerge sync for both documents on that connection, generating messages after every local commit and every received message until neither has more to send.
- **PNT-A0019-05** A joining peer shall start with empty documents and create nothing in them until its first sync with the peer it joined has completed; it then adds its `participants` entry with `joined` one more than the largest seen. Every peer shall, at least every ping interval, connect to each listed Participant whose `left` is false and with whom it has no connection, when its own `joined` is larger, ties broken by the larger id.
- **PNT-A0019-06** Peers shall send ping every 2 seconds, and treat a peer they have heard nothing from for 10 seconds as gone (MPLY-17). A Participant leaving shall set its `left` to true, send bye and close its connections. A peer that loses a connection it had with a Participant, by timeout or by a close without bye, shall set that Participant's `left` to true; it never marks a Participant it was not connected to.
- **PNT-A0019-07** A Participant shall be present to a peer while that peer has a live connection to it, or it is that peer. The Host shall be `host` if present, else the present Participant with the smallest `joined`, ties broken by id. Promotion writes `host`; a peer that finds itself the Host while `host` names a Participant marked left, or no listed Participant, writes its own id to `host`.
- **PNT-A0019-08** Duplicate connections between the same two Participants shall be closed, keeping the one opened by the smaller participant id.

## Alternatives considered
- **WebRTC with a signaling server.** Crosses NATs, but needs a server. Rejected by the owner for the first version.
- **A relay all peers connect to.** Simple routing, but it is a server and a single point of failure. Rejected by the owner.
- **automerge-repo's protocol.** Has a JavaScript and a Rust implementation, no Dart one, and brings document storage Painter does not need. Rejected.
- **A star around the Host.** Fewer connections, but the Session would fall apart when the Host leaves (MPLY-18). Rejected.

## Consequences
- Joining works only where peers can reach each other directly, such as one LAN or a VPN.
- There is no authentication or encryption; anyone who can reach a Session address can join (multiplayer.md, Open Questions).
- Each pair of Participants holds one connection, so n Participants hold n(n-1)/2.
- Two partitioned groups can briefly each name a different Host; this only changes a label.
