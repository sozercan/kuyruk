# Kuyruk

A native macOS GitHub Notifications client built with Swift and SwiftUI, featuring Liquid Glass design.

![macOS 26+](https://img.shields.io/badge/macOS-26+-blue)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- 🔔 **Real-time Notifications** — Sync and display GitHub notifications with local alerts
- 📋 **Smart Filters** — Filter by repository, reason (review requested, mentioned, assigned, etc.)
- 🏷️ **Category Groups** — Organize notifications like Apple Reminders smart lists
- ✅ **Mark as Read/Done** — Archive or mark notifications as read with swipe gestures
- 🔗 **Quick Open** — Open issues/PRs directly in browser
- 🔍 **Search** — Full-text search across all notifications
- 🎨 **Liquid Glass UI** — macOS 26 native design with translucent surfaces
- ⌨️ **Keyboard Shortcuts** — Full keyboard control for power users

## Requirements

- macOS 26.0 or later
- [GitHub](https://github.com/) account

## Installation

### Download

Download the latest release from the [Releases](https://github.com/sozercan/kuyruk/releases) page.

### Build from Source

```bash
git clone https://github.com/sozercan/kuyruk.git
cd kuyruk
xcodebuild -scheme Kuyruk -destination 'platform=macOS' build
```

## Keyboard Shortcuts

### Navigation

| Shortcut | Action |
|----------|--------|
| ⌘1 | Go to Inbox |
| ⌘2 | Go to Participating |
| ⌘3 | Go to Mentioned |
| ⌘F | Focus Search |
| ⌘K | Open Command Bar |

### Actions

| Shortcut | Action |
|----------|--------|
| ⌘R | Refresh |
| ⌘O | Open in Browser |
| ⌘⇧M | Mark as Read |
| ↑↓ | Navigate Notifications |
| ⏎ | Open Selected |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, architecture, and coding guidelines.

## Documentation

- [Architecture](docs/architecture.md) — Services, state management, data flow
- [API Integration](docs/api-integration.md) — GitHub API endpoints
- [Testing](docs/testing.md) — Test commands and patterns
- [ADRs](docs/adr/) — Architecture Decision Records

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Design inspired by [Apple Reminders](https://support.apple.com/guide/reminders/welcome/mac)
- Architecture patterns from [sozercan/kaset](https://github.com/sozercan/kaset)
- Skills from [Dimillian/Skills](https://github.com/Dimillian/Skills)
