# T01 — Foundation

Requirements: R14, R20. Suite: V17. Status: running.

Predeclared acceptance: preserve existing app/scheme and signing identity; build iPhone simulator at iOS 18 minimum in Swift 6 mode; local CubeKit package compiles independently and is linked by the app; discovered tests must execute; intentional assertion failure propagates a nonzero exit through logging; zero discovered/skipped/failed required tests must not become a passing run; result artifacts survive failures; missing resources/evidence fail explicitly.

Environment observed: Xcode 27.0 (27A266a), Apple Swift 6.4, arm64 macOS 27 host. iOS 18.5, 26.5 and 27.0 simulator runtimes installed. Exact stable-toolchain qualification remains to be checked; an installed version alone is not release-channel evidence.

Initial repository contains Hello World SwiftUI app and template tests only. Existing uncommitted project change adds the four supplied documentation references; preserved in the baseline commit.
