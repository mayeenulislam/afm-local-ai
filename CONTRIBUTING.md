# Contributing to AFM Local AI

Thanks for your interest in contributing to AFM Local AI! This is a native macOS app built with Swift and SwiftUI.

## Getting Started

### Prerequisites

- macOS 14 or later
- Xcode 16+ or Swift 6.0 toolchain
- Apple Silicon Mac recommended for full Apple Foundation Models support

### Building Locally

1. Clone the repository
2. Build with `swift build`
3. Run with `swift run LocalAI` or use `scripts/build_dev.sh` to create a `.app` bundle

```sh
swift build
swift run LocalAI
```

### Development Builds

```sh
chmod +x scripts/build_dev.sh
scripts/build_dev.sh release
open "dist/AFM Local AI.app"
```

## Development Guidelines

- Follow Swift/SwiftUI best practices and keep changes consistent with the existing codebase style
- All file operations should be local-first and respect workspace permissions
- Keep UI changes accessible (follow WCAG guidelines where applicable)
- Write tests for new functionality when possible
- Keep the app privacy-focused - no network calls by default

## Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes and test thoroughly
4. Commit your changes with clear, descriptive messages
5. Push to your fork and submit a Pull Request

## Reporting Issues

If you find a bug or have a feature request, please open an issue on GitHub with:
- A clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- macOS version and Mac model

## Code of Conduct

Be respectful and constructive in all interactions.
