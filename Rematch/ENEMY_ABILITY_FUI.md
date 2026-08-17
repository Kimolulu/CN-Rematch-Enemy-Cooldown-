# Enemy Ability Bar — settings-clean build

- Enemy Skill Cooldown Font Size, X Position and Y Position are native settings.
- X/Y are applied directly to the cooldown FontString from the current settings.
- Button creation also starts at the configured X/Y; there is no temporary 0,0 position.
- ApplySettings() reapplies layout after a setting changes.
- No icon border/corner accents, scanline, progress line, READY, or COOLDOWN label.
- Cooldown icon is desaturated while cooling; cooldown number is centered relative to
  the skill frame and uses the configured font size.
- Enemy ability tracking matches ability IDs against the active enemy pet's actual
  ability slots, so defensive/armor/buff/utility abilities are not filtered out
  merely because they are not attack skills.
