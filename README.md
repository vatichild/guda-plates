# GudaPlates

A customizable nameplate addon for World of Warcraft 1.12.1 (Vanilla) and Turtle WoW.

## Features

- **Debuff Tracking** - Shows debuffs on enemy nameplates with countdown timers
- **Rank-Aware Durations** - Correctly tracks debuff durations based on spell rank
- **Cast Bars** - Displays enemy cast bars on nameplates (requires SuperWoW)
- **Threat Indication** - Visual threat indicators for tanks
- **Health & Level Display** - Clean health bars with level and classification icons
- **Raid Icons** - Shows raid target icons on nameplates
- **Target Highlight** - Highlights your current target's nameplate

## Requirements

- World of Warcraft (Vanilla)
- **SuperWoW is highly recommended** for full functionality

## SuperWoW Support

GudaPlates works best with [SuperWoW](https://github.com/balakethelock/SuperWoW) installed. SuperWoW provides:

- **GUID-based tracking** - Accurate debuff tracking per mob, even with same-named enemies
- **Cast bar detection** - See enemy spell casts on nameplates
- **Enhanced nameplate matching** - Reliable nameplate-to-unit association

Without SuperWoW, GudaPlates will fall back to name-based tracking which may be less accurate with multiple enemies of the same name.

## Installation

1. Download and extract GudaPlates to your `Interface\AddOns\` folder
2. The folder structure should be: `Interface\AddOns\GudaPlates\`
3. Restart WoW or `/reload` if already in-game

## Slash Commands

- `/gp` or `/gudaplates` - Show available commands
- `/gp role tank` - Set role to tank (shows threat loss indicators)
- `/gp role dps` - Set role to DPS/healer (shows threat gain indicators)
- `/gp overlap` - Toggle nameplate overlap mode
- `/gp timers` - Toggle debuff countdown timers

## Debuff Duration Database

GudaPlates includes a comprehensive spell database with correct durations for all ranks of:

- Warrior debuffs (Rend, Hamstring, Thunder Clap, etc.)
- Rogue debuffs (Rupture, Garrote, Kidney Shot, etc.)
- Mage debuffs (Frostbolt, Polymorph, etc.)
- Warlock debuffs (Corruption, Curse of Agony, etc.)
- Priest debuffs (Shadow Word: Pain, etc.)
- Druid debuffs (Moonfire, Rake, etc.)
- Hunter debuffs (Serpent Sting, etc.)
- And many more...

## License

MIT License - Feel free to modify and distribute.
