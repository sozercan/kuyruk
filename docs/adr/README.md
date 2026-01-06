# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the Kuyruk project.

## What is an ADR?

An ADR is a document that captures an important architectural decision made along with its context and consequences.

## Format

Each ADR follows this template:

```markdown
# ADR-NNNN: Title

## Status

Proposed | Accepted | Deprecated | Superseded by ADR-XXXX

## Context

What is the issue that we're seeing that is motivating this decision or change?

## Decision

What is the change that we're proposing and/or doing?

## Consequences

What becomes easier or more difficult to do because of this change?
```

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-swiftui-observable-pattern.md) | SwiftUI Observable Pattern | Accepted |
| [0002](0002-github-oauth-authentication.md) | GitHub OAuth Authentication | Accepted |
| [0003](0003-liquid-glass-design.md) | Liquid Glass Design Language | Accepted |
| [0004](0004-swift-package-manager.md) | Swift Package Manager as Primary Build System | Accepted |
| [0005](0005-swiftdata-persistence.md) | SwiftData for Local Persistence | Accepted |

## Creating a New ADR

1. Copy the template above
2. Name the file `NNNN-short-title.md` (use next available number)
3. Fill in the sections
4. Add to the index in this README
5. Submit for review
