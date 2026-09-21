import CubeCore
import CubeScan
import CubeSession
import SwiftUI

struct CenterAssignmentView: View {
  @State private var assignments: [CubeColor?]
  @State private var selectedFace: Face?
  let confirm: (CenterPalette) -> Void

  init(initial: CenterPalette?, confirm: @escaping (CenterPalette) -> Void) {
    _assignments = State(
      initialValue: initial?.colors.map(Optional.some) ?? Array(repeating: nil, count: 6))
    self.confirm = confirm
  }
  private var palette: CenterPalette? { try? CenterPalette(assignments.compactMap { $0 }) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Assign center colors").font(.title.bold())
        Text(
          "Choose a front face and hold an adjacent face on top. Use those as Front and Up throughout entry. Match each face's center; use each color once."
        )
        ForEach(Face.allCases, id: \.rawValue) { face in
          Button {
            selectedFace = face
          } label: {
            HStack {
              Text(face.title)
              Spacer()
              Text(assignments[Int(face.rawValue)]?.title ?? "Choose color")
              Image(systemName: "chevron.down")
            }.frame(minHeight: 44)
          }
          .accessibilityLabel(
            "\(face.title) center, \(assignments[Int(face.rawValue)]?.title ?? "not assigned")"
          )
          .accessibilityIdentifier("center.\(face.code)")
        }
        Button("Confirm centers") { if let palette { confirm(palette) } }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(palette == nil).accessibilityIdentifier("centers.confirm")
        if assignments.compactMap({ $0 }).count == 6 && palette == nil {
          Text("Use six different center colors.").foregroundStyle(.secondary)
        }
      }.padding()
    }
    .confirmationDialog(
      "Choose center color",
      isPresented: Binding(get: { selectedFace != nil }, set: { if !$0 { selectedFace = nil } }),
      titleVisibility: .visible
    ) {
      ForEach(CubeColor.allCases, id: \.rawValue) { color in
        Button(color.title) {
          if let face = selectedFace { assignments[Int(face.rawValue)] = color }
          selectedFace = nil
        }
      }
      Button("Cancel", role: .cancel) { selectedFace = nil }
    }
  }
}

struct ManualEditorView: View {
  let draft: ManualDraft
  let saving: Bool
  let edit: (DraftEdit) -> Void
  @State private var selected: Cell?
  @State private var changingCenters = false
  @ScaledMetric(relativeTo: .body) private var cellSize = 44
  private struct Cell {
    let face: Face
    let row: Int
    let column: Int
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Match each sticker").font(.title.bold())
        Text(
          "Tap an empty square to enter its color. Keep the top edge of each face aligned with the named neighbor. Swipe the net sideways to reach every face."
        )
        Text("\(draft.missingCount) stickers left").font(.headline)
        if saving { ProgressView("Saving…").accessibilityIdentifier("editor.saving") }
        ScrollView(.horizontal) {
          Grid(horizontalSpacing: 12, verticalSpacing: 16) {
            GridRow {
              blank
              faceView(.up)
              blank
              blank
            }
            GridRow {
              faceView(.left)
              faceView(.front)
              faceView(.right)
              faceView(.back)
            }
            GridRow {
              blank
              faceView(.down)
              blank
              blank
            }
          }.padding(.horizontal, 4)
        }.defaultScrollAnchor(.center)
        Button("Change center colors") { changingCenters = true }
          .buttonStyle(.bordered).disabled(saving)
        Text(
          "Centers stay fixed. Changing their assignments preserves the other colors you entered."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }.padding()
    }
    .confirmationDialog(
      "Choose sticker color",
      isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
      titleVisibility: .visible
    ) {
      ForEach(CubeColor.allCases, id: \.rawValue) { color in
        Button(color.title) { setColor(color) }.accessibilityIdentifier("sticker.\(color.rawValue)")
      }
      Button("Clear sticker") { setColor(nil) }.accessibilityIdentifier("sticker.clear")
      Button("Cancel", role: .cancel) { selected = nil }
    }
    .sheet(isPresented: $changingCenters) {
      NavigationStack {
        CenterAssignmentView(initial: draft.palette) {
          edit(.centers($0))
          changingCenters = false
        }
        .navigationTitle("Center colors")
        .toolbar { Button("Cancel") { changingCenters = false } }
      }
    }
  }
  private var blank: some View { Color.clear.frame(width: cellSize * 3 + 8, height: 1) }
  private func faceView(_ face: Face) -> some View {
    VStack(spacing: 6) {
      Text(face.title).font(.headline)
      Text("Top: \(face.topNeighbor.title)").font(.caption)
      Grid(horizontalSpacing: 4, verticalSpacing: 4) {
        ForEach(0..<3) { row in
          GridRow {
            ForEach(0..<3) { column in
              let color = draft.cells[Int(face.rawValue) * 9 + row * 3 + column]
              let center = row == 1 && column == 1
              Button {
                if center {
                  changingCenters = true
                } else {
                  selected = Cell(face: face, row: row, column: column)
                }
              } label: {
                Text(color.map { String($0.title.prefix(1)) } ?? "+")
                  .font(.headline).frame(width: cellSize, height: cellSize)
                  .foregroundStyle(
                    color == nil ? Color.primary : (color == .blue ? Color.white : Color.black)
                  )
                  .background(
                    color?.swatch ?? Color(uiColor: .systemGray5),
                    in: RoundedRectangle(cornerRadius: 6)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.6), lineWidth: 1))
              }
              .buttonStyle(.plain).disabled(saving)
              .accessibilityLabel(
                "\(face.title), row \(row + 1), column \(column + 1), \(color?.title ?? "Empty")\(center ? ", center" : "")"
              )
              .accessibilityIdentifier("cell.\(face.code).\(row).\(column)")
            }
          }
        }
      }
      Button("Rotate 90°") { edit(.rotate(face, .clockwise)) }
        .font(.caption).frame(minHeight: 44).disabled(saving)
        .accessibilityLabel("Rotate \(face.title) colors clockwise")
        .accessibilityIdentifier("rotate.\(face.code)")
    }
  }
  private func setColor(_ color: CubeColor?) {
    if let selected {
      edit(.sticker(face: selected.face, row: selected.row, column: selected.column, color: color))
    }
    selected = nil
  }
}

extension Face {
  var title: String { ["Up", "Right", "Front", "Down", "Left", "Back"][Int(rawValue)] }
  var code: String { ["U", "R", "F", "D", "L", "B"][Int(rawValue)] }
  var topNeighbor: Face { [.back, .up, .up, .front, .up, .up][Int(rawValue)] }
}
extension CubeColor {
  var title: String { rawValue.capitalized }
  var swatch: Color {
    let rgb: (Double, Double, Double)
    switch self {
    case .white: rgb = (245, 245, 245)
    case .yellow: rgb = (248, 214, 43)
    case .red: rgb = (216, 56, 50)
    case .orange: rgb = (242, 140, 40)
    case .blue: rgb = (36, 106, 194)
    case .green: rgb = (39, 134, 75)
    }
    return Color(.sRGB, red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, opacity: 1)
  }
}
