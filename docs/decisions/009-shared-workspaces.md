# 009. Workspaces live in an in-memory session document that Participants share by joining; a file stores one only through Flash

Status: accepted   (supersedes: 006; superseded by: none)
Date: 2026-11-11
Relates to: WKSP-1, WKSP-2, WKSP-3, WKSP-4, WKSP-5, WKSP-6, WKSP-7, WKSP-21, WKSP-29, WKSP-31, WKSP-32, WKSP-33, WKSP-34, WKSP-35, WKSP-37, WKSP-38

## Context
Decision 006 kept each participant's layout private and shared it only by one-way following. The owner replaced following with joining: Members of one workspace all edit it, so a workspace is shared mutable state and must converge under concurrent edits (WKSP-35). Decision 006's reasons for a separate, Flash-only workspace section still hold: layout churn should not change the file on every save, and a damaged layout must not stop a document loading. Who may Flash changed from the Host to any Participant.

## Decision
- **PNT-A0015-01** The Painter shall keep a session document, an Automerge document separate from the content document, that is never saved. Outside a Session it exists with one Participant, so one code path serves both cases.
- **PNT-A0015-02** The session document's root map shall hold `participants` (map from participant id to `name`, `joined` (int), `workspace` (workspace id), optional `previousWorkspace`, `addresses` (list of "host:port" strings joined by spaces) and `left` (bool)), `host` (participant id), `workspaces` (map from workspace id to a map holding `nodes`, see docs/decisions/010-pane-layout-tree.md), `engine` (int) and optional `storedWorkspace` (the Host's file's workspace section as JSON text).
- **PNT-A0015-03** A Participant's Workspace shall be the one named by its `participants` entry's `workspace`. Joining sets it to the other Participant's and records the old one in `previousWorkspace` (WKSP-37).
- **PNT-A0015-04** When a workspace is named, as `workspace` or `previousWorkspace`, by no Participant whose `left` is false, the Participant whose action or observation made it so shall delete it from `workspaces` (WKSP-21). Presence is not consulted, so a newcomer still connecting to the rest of the mesh keeps its workspace. A peer never deletes the workspace its own Participant names. A peer active in a Session that finds its own `left` true sets it back to false, and one whose own workspace is missing recreates it from the layout it last showed and names it again.
- **PNT-A0015-05** While a Member drags a splitter or pans, zooms or rotates a canvas, the Painter shall commit the change to the session document at most every 50 ms and once more when the gesture ends, so peers see it within WKSP-34's 100 ms.
- **PNT-A0015-06** A document file shall store a workspace only in its workspace section, written only by Flash (by any Participant, into the file that Participant saves to) or by Save As copying the source file's section. Save leaves the section as read.
- **PNT-A0015-07** The workspace section shall be version 2 JSON: `{"version": 2, "root": node}`, where a node is either `{"split": "row" | "column", "parts": [{"share": number, "node": node}, ...]}` or `{"pane": {"mode": name, "state": {mode name: state}}}`. A Canvas state is `{"center": {"x": number, "y": number}, "extent": number, "rotation": number}` and a Manual state is `{"help": name}`. Version 1 sections are Unusable.

## Alternatives considered
- **Keep following (decision 006).** No shared mutable layout, but the owner wants joined Members to edit together. Rejected.
- **Workspaces inside the content document.** One document to sync, but every pan would enter the saved history and Flash would no longer be the only way a layout reaches the file. Rejected.
- **One Automerge document per workspace.** Lets a discarded workspace's history be freed, but multiplies sync streams per peer. Rejected while sessions are short-lived; the session document is dropped when the Session ends.
- **Sidecar file, layout written on every save, or layout only in user settings.** Rejected for the reasons in decision 006: portability, version-control churn, and one layout per file.

## Consequences
- The session document's history grows with every committed pan for the length of a Session; it is discarded when the Session ends.
- Explicit Flash means a user can lose layout changes they forgot to flash.
- Layout changes are not document changes, so they neither mark the document modified nor enter undo history.
- Headless export ignores the workspace section.
- Decision 006 is superseded entirely; its accepted points are restated here.

## Revisit if
Session documents grow large enough to slow joining, or users routinely lose layouts by forgetting to Flash.
