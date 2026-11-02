# Architecture

## Current Constraints

- The application is intended to use Flutter and Dart.
- macOS is the current target; Linux, Windows, and Android are future targets with no rollout order decided.

## Architectural Priorities

- Prefer cohesive components with clear responsibilities and narrow interfaces. Minimize unnecessary dependencies and cross-component knowledge so changes can be developed, tested, and revised with limited impact on unrelated parts.
- Make component ownership, public contracts, and permitted dependencies clear when planning work, especially when work may be implemented independently.
- Treat modularity as a priority, not as a requirement to use a particular architecture or split code into packages. Choose concrete boundaries and mechanisms based on the product requirements and runnable evidence.

## Decisions Not Yet Made

The following remain undecided until product requirements and runnable evidence exist:

- Rendering and canvas implementation.
- State management.
- Document representation and file format.
- Platform integration.

Do not select packages, patterns, or a directory layout in advance.

## Decision Process

Record durable technical choices in the [Architecture Decision Records](decisions/README.md) directory using its ADR convention. Do not record undecided proposals as decisions.
