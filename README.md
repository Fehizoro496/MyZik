# my_zik

A Flutter music-player app implementing the **Music Player** design from
Claude Design (a dark-themed mobile player with a blue→violet accent gradient).

## Screens

- **Home** — greeting, category chips, a "Discover weekly" feature card, and a
  "Top daily playlists" list, with a frosted floating bottom nav.
- **Now Playing** — circular artwork, track info, lyrics, a scrubbable progress
  bar and transport controls (play/pause toggles the live progress ticker).
- **My Music** — filter chips, a scrollable song list, and a frosted mini player.

Tapping any track opens Now Playing; the bottom nav / back buttons move between
screens. On phones the UI is edge-to-edge; on wide viewports (web/desktop) it is
framed inside a 390×844 phone mockup.

## Structure

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App entry, `PlayerShell` (navigation + phone frame) |
| `lib/player_controller.dart` | Playback + navigation state, progress ticker |
| `lib/models.dart` | `Track` / `Category` models and sample data |
| `lib/theme.dart` | Palette + dark theme (**Plus Jakarta Sans** via `google_fonts`) |
| `lib/widgets.dart` | Shared widgets (status bar, album art, chips, track row); UI icons via **Iconly** (`flutter_iconly`) |
| `lib/screens/` | The three screens |

## Running

```bash
flutter pub get
flutter run          # mobile / desktop
flutter run -d chrome # web
flutter test         # widget + layout tests
```
