# Graphics source and qualification inventory

This inventory records sources, not a claim that every required asset is complete. Canonical A01–A08 requirements remain in Documentation/cube-app-specification.md.

| Asset | Source and origin | Current scope |
|---|---|---|
| A02 procedural cube | Original CubeGeometry/CubeRotation in CubeCore; CubeSceneModel/CubePreviewScreen in the app. Bodies/stickers generated with RealityKit meshes; text glyphs generated using the platform system font. Two procedural directional lights and a virtual camera. No downloaded mesh, texture or font. | Static editable-input preview implemented; discrete mathematics and entity transforms tested; light/dark portrait simulator screenshots inspected. Turn animation, rendered long-run snapping, broader accessibility/layout and physical validation pending. |
| A01 icon | Not yet produced | Open |
| A03 turn/regrip overlays | Not yet produced | Open |
| A04 onboarding/help illustrations | Not yet produced | Open |
| A05 controls | System symbols and explicit text/accessibility labels in implemented screens | Full inventory and minimum-OS visual qualification pending |
| A06 editor/capture graphics | Original SwiftUI manual grid, palette and review markers | Manual portion implemented; camera/crop/quality graphics pending |
| A07 completion art | Not yet produced | Open |
| A08 store screenshots | Not yet produced | Requires actual qualified Release build |

The screenshot files under docs/evidence are implementation evidence, not App Store screenshots or marketing claims. Human narration/effect assets remain a separate T08 requirement.
