import Testing
import UIKit

// A05 inventory: every SF Symbol referenced by `Image(systemName:)` /
// `Button(_, systemImage:)` in cubeguide/. Re-grep the app target and update
// this list when symbols are added or removed; this test fails closed on drift
// only for listed symbols, so keep it in sync by review.
@Test("A05: every control symbol used by the app exists on this runtime")
@MainActor
func controlSymbolsExistOnRuntime() {
  let symbols = [
    "arrow.clockwise",
    "arrow.left.and.right",
    "arrow.up",
    "camera",
    "camera.circle.fill",
    "camera.viewfinder",
    "checkmark.circle",
    "checkmark.circle.fill",
    "chevron.down",
    "chevron.left",
    "circle",
    "cube",
    "exclamationmark.circle.fill",
    "exclamationmark.triangle",
    "gear",
    "gearshape",
    "hand.raised",
    "light.max",
    "plus",
    "questionmark.circle",
    "rotate.3d",
    "rotate.right",
    "square.3.layers.3d.top.filled",
    "square.grid.3x3",
    "square.grid.3x3.fill",
  ]
  #expect(symbols.count == 25)
  for symbol in symbols {
    #expect(UIImage(systemName: symbol) != nil, "Missing symbol: \(symbol)")
  }
}
