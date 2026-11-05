# Structure
The overall structure of this application from a high level, but also how it interacts with the system.
## Status
Unimplemented.
## Context

Computer applications are often single-modal; they are intended to be interacted with via the terminal _or_ a graphical window, not both. But, this is awfully limiting. It means that you can't headlessly - without having a graphical session (like X11 or wayland) - take a `.paint` file and render to a PNG, or a MP4, or whatever for example.

## Decision

- The Application shall be able to render the canvas to a PNG image file headlessly.


## Consequences

The systems are going to be much less coupled to a window or a graphical environment.
