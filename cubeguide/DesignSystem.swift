import SwiftUI

/// Shared visual language for every screen (spec section 12: restrained,
/// system font/styles/colors, 44-point targets, scrollable at large sizes).
/// Layout-only: no text, identifier, or behavior changes live here.

/// A full-width content card on the system secondary background.
struct CardStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(uiColor: .secondarySystemBackground),
        in: RoundedRectangle(cornerRadius: 16))
  }
}

/// Full-width call to action using the real system bordered styles.
/// The expanding frame lives inside the button label: bordered backgrounds
/// wrap the label, so an outer frame only widens the tap area and leaves a
/// centered pill. Accessibility labels match the plain `Button` title.
struct CTAButton: View {
  enum Kind { case primary, secondary }
  let title: String
  let symbol: String?
  let identifier: String?
  let kind: Kind
  let role: ButtonRole?
  let action: () -> Void

  init(
    _ title: String, symbol: String? = nil, identifier: String? = nil,
    kind: Kind, role: ButtonRole? = nil, action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.identifier = identifier
    self.kind = kind
    self.role = role
    self.action = action
  }

  var body: some View {
    Group {
      if kind == .primary {
        button.buttonStyle(.borderedProminent)
      } else {
        button.buttonStyle(.bordered)
      }
    }
    .controlSize(.large)
    .modifier(OptionalIdentifier(identifier))
  }

  private var button: some View {
    Button(role: role, action: action) {
      HStack(spacing: 8) {
        if let symbol {
          Image(systemName: symbol).accessibilityHidden(true)
        }
        Text(title)
      }
      .frame(maxWidth: .infinity, minHeight: 50)
    }
  }
}

private struct OptionalIdentifier: ViewModifier {
  let identifier: String?
  init(_ identifier: String?) { self.identifier = identifier }
  func body(content: Content) -> some View {
    if let identifier {
      content.accessibilityIdentifier(identifier)
    } else {
      content
    }
  }
}

/// A tappable menu row inside a card (44-point target, system symbol + label).
struct MenuRow: View {
  let title: String
  let symbol: String
  let identifier: String
  let role: ButtonRole?
  let action: () -> Void

  init(
    _ title: String, symbol: String, identifier: String, role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.identifier = identifier
    self.role = role
    self.action = action
  }

  var body: some View {
    Button(role: role, action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 18))
          .frame(width: 28)
          .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
          .accessibilityHidden(true)
        Text(title)
        Spacer()
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
  }
}

/// Scrollable screen scaffold with consistent spacing.
struct ScreenScaffold<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
  }
}

extension View {
  func card() -> some View { modifier(CardStyle()) }
}
