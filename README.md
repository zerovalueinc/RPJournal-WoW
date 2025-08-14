# Character Memory - WoW RP Addon

A World of Warcraft addon for roleplayers to track relationships with other players and NPCs, featuring a leveling system and journal functionality.

## Version: 0.0.4

## Features

- **Per-target memory journal** - Store first/last seen context and personal notes for players and NPCs
- **Relationship leveling system** - XP-based progression with cooldowns and tiers
- **Movable UI panel** - Shows key relationship info and progress bars
- **Slash commands** - Easy access to notes, sharing, toggles, and manual XP adjustments
- **Parchment-style UI** - Beautiful, immersive interface for roleplay
- **Per-character persistence** - SavedVariables ensure your memories persist across sessions

## Installation

1. Download the latest release
2. Extract the `CharacterMemory` folder to your `World of Warcraft/_retail_/Interface/AddOns/` directory
3. Restart World of Warcraft or reload your UI (`/reload`)

## Usage

### Slash Commands
- `/cm` or `/rpmemory` - Toggle the main journal interface
- `/cm target` - Show/hide the target panel
- `/cm note [text]` - Add a note about your current target
- `/cm share` - Share relationship info with your target
- `/cm xp [amount]` - Manually adjust XP for current target

### Features
- **Automatic tracking**: The addon automatically records when you first meet someone and updates your last encounter
- **Zone context**: Records where you met and last saw each person
- **Relationship levels**: Build relationships through interactions and gain XP
- **Journal entries**: Add personal notes and memories about each person

## Development

This addon is built for WoW Retail (Interface version 110100) and requires no external libraries.

### Project Structure
```
CharacterMemory/
├── CharacterMemory.lua      # Main addon logic
├── CharacterMemory.toc      # Addon manifest
├── CharacterMemory.xml      # UI definitions
├── CM_Achievements.lua      # Achievement system
├── CM_Journal.lua          # Journal functionality
├── RPBio.lua              # Character bio system
├── RPBio.xml              # Bio UI definitions
├── Art/                   # TGA texture assets
└── media/                 # PNG texture assets
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in-game
5. Submit a pull request

## License

This project is open source. Please respect the WoW addon development community guidelines.

## Support

For issues, feature requests, or questions, please open an issue on GitHub.

---

**Note**: This addon is currently in early development (v0.0.4). Features may change and bugs may exist. Please report any issues you encounter.

