# Settings: Behavior

Behavior of appearance settings, as observed by the user. Notation: [EARS+](../README.md#requirement-notation-ears). Implementation is in [theme-and-palettes](theme-and-palettes.md).

## Theme Modes and Palettes

- **PNT-THM-001** The Settings shall support System, Light, and Dark theme modes.
  Source: T-007; [theme-and-palettes](theme-and-palettes.md).
- **PNT-THM-009** WHILE the theme mode is System, the Painter shall follow the system brightness.
  Source: T-007.
- **PNT-THM-002** The Settings shall keep the selected light palette and the selected dark palette independent of each other.
  Source: T-007; [theme-and-palettes](theme-and-palettes.md).
- **PNT-THM-003** The Settings shall provide Gruvbox Light and Gruvbox Dark as built-in palettes.
  Source: T-007; [theme-and-palettes](theme-and-palettes.md).
- **PNT-THM-004** The Settings shall allow the user to create, edit, and save
  custom palettes without changing built-in palettes.
  Source: T-007; T-010; [theme-and-palettes](theme-and-palettes.md).
- **PNT-THM-005** WHILE a palette is active, the Painter shall draw program UI colors from that palette.
  Source: T-007; [theme-and-palettes](theme-and-palettes.md).
- **PNT-THM-008** The Settings shall present appearance controls as selectable Settings pane content.
  Source: T-007.

## Persistence

- **PNT-THM-010** WHEN the Painter restarts, the Settings shall restore the theme mode, both palette selections, and all custom palette colors.
  Source: T-007; [theme-and-palettes](theme-and-palettes.md).
- **PNT-THM-011** IF the stored settings are missing, malformed, or unavailable, THEN the Settings shall fall back to default values and the Painter shall continue starting.
  Source: T-007; [theme-and-palettes](theme-and-palettes.md).

## Canvas Paper

The paper and marks are Canvas behavior and are specified in [canvas behavior](../canvas/behavior.md#paper-and-marks) (PNT-THM-006, PNT-THM-007).

