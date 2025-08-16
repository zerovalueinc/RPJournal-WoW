# Changelog

All notable changes to the Character Memory WoW addon will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.5] - 2025-01-15

### Fixed
- **Critical Bug Fix**: Fixed function scope issue causing "attempt to call global 'awardToAllGroupmates' (a nil value)" error
- **Dungeon Completion Tracking**: Resolved issue where dungeon completion rewards were not being awarded to group members
- **Function Order**: Moved `awardToAllGroupmates` and `incStatForAllGroupmates` functions before `maybeCreditDungeonOnExit` to fix Lua scope issues

### Technical
- **Hotfix**: Emergency fix for WoW update compatibility issues
- **Code Organization**: Improved function ordering to prevent nil value errors

## [0.0.4] - 2024-12-19

### Added
- **Character Memory System**: Core relationship tracking functionality for players and NPCs
- **XP-Based Relationship Levels**: Automatic XP gain through interactions and activities
- **Journal Interface**: Parchment-style UI for viewing and managing relationship data
- **Achievement System**: Trackable achievements with XP rewards
- **Bio Sharing**: Cross-user bio sharing functionality via addon messages
- **Slash Commands**: Complete command system for addon interaction

### Changed
- **UI Framework**: Implemented movable UI panels with proper combat handling
- **Data Persistence**: Enhanced SavedVariables structure for per-character data storage
- **Settings Integration**: Modern settings panel with RP Bio configuration

### Technical
- **Performance Optimization**: Hoisted hot globals to locals for reduced CPU usage
- **Error Handling**: Added defensive guards for WoW API calls
- **Memory Management**: Efficient data structures for relationship tracking

## [0.0.3] - Previous Release

### Added
- **RP Character Sheet**: Added RPBio.xml/RPBio.lua scrollable character sheet with nested schema (RPJournalDB)
- **Settings Integration**: Settings button to open character sheet above settings (DIALOG strata)
- **UI Improvements**: Tightened RP Bio settings layout and aligned RP Preferences
- **Icon Support**: Added compact addon icon via TOC IconTexture

### Changed
- **Settings Layout**: Removed Relationships section from settings panel
- **UI Positioning**: Improved label positioning with labels above inputs
- **Input Sizing**: Adjusted input widths and spacings for better fit within Settings

## [0.0.2] - Previous Release

### Added
- **RP Bio Settings**: Added RP Bio settings subpage
- **Journal Request Bio**: Implemented bio request functionality in journal
- **Payload Hydration**: Added payload hydration system
- **Layout Polish**: General UI layout improvements

### Changed
- **UI Overhaul**: Complete label positioning overhaul for settings panel
- **Input Layout**: Labels positioned above inputs with proper spacing
- **Icon Integration**: Added compact addon icon support

---

## Version History Notes

- **v0.0.5**: Current stable version - Hotfix for critical function scope bug
- **v0.0.4**: Previous development version - Early alpha with basic functionality
- **v0.0.3**: Previous stable release with RP Character Sheet features
- **v0.0.2**: Initial stable release with core journal functionality

## Future Plans

### Planned for v0.1.0
- Bug fixes and stability improvements
- Enhanced UI responsiveness
- Additional relationship tracking features
- Performance optimizations

### Planned for v0.2.0
- Achievement system improvements
- Enhanced bio sharing functionality
- Additional customization options
- Cross-realm compatibility improvements
