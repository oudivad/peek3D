import Foundation
import simd

/// 3MF reader: a ZIP archive holding an XML model. Unlike STL, the format
/// describes a scene — reusable objects assembled through transforms — which
/// has to be flattened before anything can be drawn.
///
/// Slicers complicate this further. Bambu Studio and OrcaSlicer write their
/// project files with the production extension, where the main model carries no
/// mesh at all: each object lives in its own file inside the archive, pointed
/// at by a `p:path` attribute. Since that is the shape of most 3MF files people
/// actually have on disk, following those references is not optional.
public enum ThreeMFLoader {

    /// Identifies an object by the model file it lives in and its id there.
    /// Ids restart at 1 in every file, so the path is part of the identity.
    struct ObjectRef: Hashable {
        let model: String
        let id: String
    }

    public static func load(data: Data) throws -> Mesh {
        let archive = try ZipArchive(data: data)
        let rootPath = try modelPath(in: archive)

        // Model files are parsed on demand: a project may hold dozens of
        // objects, and a preview rarely needs every one of them.
        var parsers = [String: ModelParser]()
        func parser(for path: String) throws -> ModelParser {
            if let existing = parsers[path] { return existing }
            let parser = ModelParser()
            guard parser.parse(try archive.contents(of: path)) else {
                throw MeshError.malformed("unreadable 3MF XML in \(path)")
            }
            parsers[path] = parser
            return parser
        }

        let root = try parser(for: rootPath)
        var corners = [SIMD3<Float>]()

        /// Applies component transforms recursively, across model files. The
        /// depth limit guards against a file whose objects reference each other
        /// in a cycle.
        func flatten(_ ref: ObjectRef, _ transform: simd_float4x4, depth: Int) {
            guard depth < 16,
                  let model = try? parser(for: ref.model),
                  let object = model.objects[ref.id] else { return }

            for tri in object.triangles {
                for index in [tri.0, tri.1, tri.2] {
                    guard index >= 0, index < object.vertices.count else { continue }
                    let p = object.vertices[index]
                    let t = transform * SIMD4<Float>(p.x, p.y, p.z, 1)
                    corners.append(SIMD3<Float>(t.x, t.y, t.z))
                }
            }

            for component in object.components {
                // Without a path of its own, a component refers to an object in
                // the same file as the one holding it.
                let target = ObjectRef(model: component.path.map(normalize) ?? ref.model,
                                       id: component.objectID)
                flatten(target, transform * component.transform, depth: depth + 1)
            }
        }

        for item in root.buildItems {
            flatten(ObjectRef(model: item.path.map(normalize) ?? rootPath, id: item.objectID),
                    item.transform, depth: 0)
        }

        // Some exporters omit the <build> section; show every meshed object
        // rather than render an empty view.
        if corners.isEmpty {
            for id in root.objects.keys {
                flatten(ObjectRef(model: rootPath, id: id), matrix_identity_float4x4, depth: 0)
            }
        }

        guard !corners.isEmpty else { throw MeshError.empty }
        var mesh = try MeshBuilder.build(corners: corners, format: "3MF")
        mesh.unit = root.unit
        return mesh
    }

    /// Paths inside the package are absolute, archive entries are not.
    private static func normalize(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    /// The package relationships name the main model; `3D/3dmodel.model` is
    /// only a very widespread convention.
    private static func modelPath(in archive: ZipArchive) throws -> String {
        if let rels = try? archive.contents(of: "_rels/.rels"),
           let text = String(data: rels, encoding: .utf8) {
            for chunk in text.components(separatedBy: "<Relationship").dropFirst()
            where chunk.contains("3dmodel") {
                if let target = attribute("Target", in: chunk) {
                    let path = normalize(target)
                    if archive.entries[path] != nil { return path }
                }
            }
        }
        if archive.entries["3D/3dmodel.model"] != nil { return "3D/3dmodel.model" }
        if let any = archive.entries.keys.first(where: { $0.hasSuffix(".model") }) { return any }
        throw MeshError.malformed("no 3MF model in the archive")
    }

    private static func attribute(_ name: String, in chunk: String) -> String? {
        guard let r = chunk.range(of: "\(name)=\"") else { return nil }
        let rest = chunk[r.upperBound...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }

    // MARK: Intermediate model

    struct Object {
        var vertices: [SIMD3<Float>] = []
        var triangles: [(Int, Int, Int)] = []
        var components: [Reference] = []
    }

    /// A pointer to an object, possibly in another file of the archive.
    struct Reference {
        let objectID: String
        /// Set by the production extension's `p:path`; nil means "this file".
        let path: String?
        let transform: simd_float4x4
    }

    /// Streaming parse: a typical 3MF print model easily exceeds 100 MB once
    /// inflated, and holding a whole DOM would be needlessly expensive inside a
    /// memory-constrained extension.
    final class ModelParser: NSObject, XMLParserDelegate {
        var objects = [String: Object]()
        var buildItems = [Reference]()
        var unit: String?
        private var currentID: String?
        private var current = Object()

        func parse(_ data: Data) -> Bool {
            let parser = XMLParser(data: data)
            parser.delegate = self
            // Namespace processing applies to element names only: attributes
            // keep their prefix, so `p:path` stays `p:path` in the dictionary.
            parser.shouldProcessNamespaces = true
            return parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attr: [String: String]) {
            switch name {
            case "model":
                unit = Self.unitSymbol(attr["unit"])
            case "object":
                currentID = attr["id"]
                current = Object()
            case "vertex":
                current.vertices.append(SIMD3<Float>(
                    Float(attr["x"] ?? "") ?? 0,
                    Float(attr["y"] ?? "") ?? 0,
                    Float(attr["z"] ?? "") ?? 0))
            case "triangle":
                if let a = Int(attr["v1"] ?? ""), let b = Int(attr["v2"] ?? ""), let c = Int(attr["v3"] ?? "") {
                    current.triangles.append((a, b, c))
                }
            case "component":
                if let id = attr["objectid"] {
                    current.components.append(Reference(objectID: id,
                                                        path: Self.externalPath(attr),
                                                        transform: Self.matrix(attr["transform"])))
                }
            case "item":
                if let id = attr["objectid"] {
                    buildItems.append(Reference(objectID: id,
                                                path: Self.externalPath(attr),
                                                transform: Self.matrix(attr["transform"])))
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            if name == "object", let id = currentID {
                objects[id] = current
                currentID = nil
                current = Object()
            }
        }

        /// The production extension's `path` attribute, whatever prefix the
        /// file binds its namespace to — `p:` by convention, but nothing in the
        /// specification requires it.
        static func externalPath(_ attr: [String: String]) -> String? {
            if let direct = attr["path"] { return direct }
            return attr.first { $0.key.hasSuffix(":path") }?.value
        }

        /// 3MF spells its units out in words; the preview shows the symbol.
        static func unitSymbol(_ name: String?) -> String? {
            switch name {
            case "micron":     return "µm"
            case "millimeter": return "mm"
            case "centimeter": return "cm"
            case "meter":      return "m"
            case "inch":       return "in"
            case "foot":       return "ft"
            default:           return name == nil ? "mm" : nil   // mm is the format's default
            }
        }

        /// 3MF writes an affine matrix as 12 numbers: three basis columns then
        /// the translation, the last column being implicit.
        static func matrix(_ text: String?) -> simd_float4x4 {
            guard let text else { return matrix_identity_float4x4 }
            let v = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Float($0) }
            guard v.count >= 12 else { return matrix_identity_float4x4 }
            return simd_float4x4(columns: (
                SIMD4<Float>(v[0], v[1], v[2],  0),
                SIMD4<Float>(v[3], v[4], v[5],  0),
                SIMD4<Float>(v[6], v[7], v[8],  0),
                SIMD4<Float>(v[9], v[10], v[11], 1)))
        }
    }
}
