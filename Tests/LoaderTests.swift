import Foundation
import AppKit
import simd

/// Checks the loaders against the files in Tests/fixtures.
///
/// A real XCTest harness would need Xcode; this standalone program keeps the
/// safety net that matters: every format yields coherent geometry, and every
/// geometry yields an image.
@main
enum LoaderTests {

    /// What we know about the fixtures regardless of the format carrying them:
    /// the cube is 1×1×1, the sphere 2×2×2.
    struct Expectation {
        let file: String
        let triangles: Int
        let size: SIMD3<Float>
        /// Vertex count expected after welding and splitting on sharp edges.
        let vertices: Int?
    }

    static let expectations: [Expectation] = [
        // The cube's 8 corners give 24 vertices: three face orientations meet at
        // each, 90° apart, well past the crease angle.
        .init(file: "cube.stl",       triangles: 12,   size: [1, 1, 1], vertices: 24),
        .init(file: "cube_ascii.stl", triangles: 12,   size: [1, 1, 1], vertices: 24),
        .init(file: "cube.obj",       triangles: 12,   size: [1, 1, 1], vertices: 24),
        .init(file: "cube.ply",       triangles: 12,   size: [1, 1, 1], vertices: 24),
        // The binary PLY carries its own normals, one per corner, so welding
        // happens on the position-and-normal pair.
        .init(file: "cube_bin.ply",   triangles: 12,   size: [1, 1, 1], vertices: 8),
        // The 3MF composes two transforms: a translation then a scale.
        .init(file: "cube.3mf",       triangles: 12,   size: [1, 1, 2], vertices: 24),
        // A smooth surface: normals average together and the vertex count falls
        // well below the three per triangle of a raw STL.
        .init(file: "sphere.stl",     triangles: 1152, size: [2, 2, 2], vertices: nil),
        // A slicer project: the main model holds no mesh at all, only a
        // reference to a separate file inside the archive. This is what Bambu
        // Studio and OrcaSlicer write, and it is the shape of 3MF most people
        // actually have on disk.
        .init(file: "slicer_project.3mf", triangles: 12, size: [2, 1, 3], vertices: 24),
        // A CAD part: the triangle count depends on tessellation, so only the
        // dimensions are checked — those are exact.
        .init(file: "bracket.step",   triangles: 0,    size: [60, 40, 15], vertices: nil),
    ]

    static func main() {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
                       ? CommandLine.arguments[1] : "Tests/fixtures")
        var failures = 0

        for expected in expectations {
            let url = root.appendingPathComponent(expected.file)
            do {
                let mesh = try MeshDocument.load(url: url)
                var problems = [String]()

                if expected.triangles > 0, mesh.triangleCount != expected.triangles {
                    problems.append("\(mesh.triangleCount) triangles instead of \(expected.triangles)")
                }
                if let v = expected.vertices, mesh.positions.count != v {
                    problems.append("\(mesh.positions.count) vertices instead of \(v)")
                }
                if simd_length(mesh.size - expected.size) > 1e-3 {
                    problems.append("size \(mesh.size) instead of \(expected.size)")
                }
                if mesh.normals.count != mesh.positions.count {
                    problems.append("normals and positions out of step")
                }
                if mesh.normals.contains(where: { abs(simd_length($0) - 1) > 1e-4 }) {
                    problems.append("non-unit normals")
                }
                if mesh.indices.contains(where: { Int($0) >= mesh.positions.count }) {
                    problems.append("index out of bounds")
                }
                if mesh.indices.count % 3 != 0 {
                    problems.append("index count is not a multiple of 3")
                }
                // The wireframe is built with the scene and hidden until the
                // viewer asks for it; above the triangle limit it is not built
                // at all, and the checkbox goes with it.
                let scene = SceneBuilder.scene(for: mesh, darkBackground: false)
                let wire = scene.rootNode.childNode(withName: SceneBuilder.wireframeName,
                                                    recursively: true)
                if mesh.triangleCount <= SceneBuilder.wireframeLimit {
                    if wire == nil {
                        problems.append("no wireframe node")
                    } else if wire?.isHidden != true {
                        problems.append("wireframe visible by default")
                    }
                } else if wire != nil {
                    problems.append("wireframe built past the triangle limit")
                }

                // A render that fails silently would mean a blank thumbnail in
                // the Finder, so check that an image actually comes out.
                if Thumbnailer.image(for: mesh, size: CGSize(width: 64, height: 64), scale: 1) == nil {
                    problems.append("could not render")
                }

                if problems.isEmpty {
                    print("  ✓ \(expected.file) — \(mesh.sourceFormat), \(mesh.triangleCount) triangles")
                } else {
                    print("  ✗ \(expected.file) — \(problems.joined(separator: " ; "))")
                    failures += 1
                }
            } catch {
                print("  ✗ \(expected.file) — \(error.localizedDescription)")
                failures += 1
            }
        }

        // An unresolved string gives itself away by returning its own key, which
        // is what happens when an .lproj was not copied into the bundle.
        for key in ["error.empty", "menu.handover", "handover.title"] where L(key) == key {
            print("  ✗ missing translation for \"\(key)\"")
            failures += 1
        }
        if failures == 0 { print("  ✓ strings resolve") }

        // An unreadable file must produce a clear error, not a crash.
        let corrupt = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek3d-corrupt.stl")
        try? Data("solid this is not a mesh".utf8).write(to: corrupt)
        do {
            _ = try MeshDocument.load(url: corrupt)
            print("  ✗ corrupt file — accepted when it should have been rejected")
            failures += 1
        } catch {
            print("  ✓ corrupt file — rejected: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: corrupt)

        print(failures == 0 ? "\nAll checks pass." : "\n\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
