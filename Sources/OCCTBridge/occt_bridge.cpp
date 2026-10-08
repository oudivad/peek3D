#include "occt_bridge.h"

#include <STEPControl_Reader.hxx>
#include <IGESControl_Reader.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <BRep_Tool.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopLoc_Location.hxx>
#include <Poly_Triangulation.hxx>
#include <Standard_Version.hxx>
#include <Message.hxx>
#include <Message_PrinterOStream.hxx>

#include <cstring>
#include <cstdio>
#include <string>
#include <vector>
#include <algorithm>

namespace {

char *duplicate(const std::string &s) {
    char *out = static_cast<char *>(std::malloc(s.size() + 1));
    if (out) std::memcpy(out, s.c_str(), s.size() + 1);
    return out;
}

/// By default OpenCASCADE writes its warnings to standard output. Inside a
/// Quick Look extension that stream does not exist, so we silence it once and
/// for all; otherwise some files trigger pointless writes.
void silenceOCCT() {
    static bool done = false;
    if (done) return;
    done = true;
    Message::DefaultMessenger()->RemovePrinters(STANDARD_TYPE(Message_PrinterOStream));
}

bool isIGES(const std::string &path) {
    size_t dot = path.find_last_of('.');
    if (dot == std::string::npos) return false;
    std::string ext = path.substr(dot + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    return ext == "iges" || ext == "igs";
}

/// Turns the quality index into meshing parameters.
///
/// Linear deflection is relative to the part's diagonal: a two-metre frame and
/// a ten-millimetre screw should produce meshes of comparable fineness on
/// screen.
void meshingParameters(int quality, double diagonal,
                       double &linear, double &angular) {
    switch (quality) {
        case 0:  linear = diagonal * 4e-3;  angular = 0.6;  break; // thumbnail
        case 2:  linear = diagonal * 5e-4;  angular = 0.2;  break; // careful render
        default: linear = diagonal * 1.5e-3; angular = 0.35; break; // preview
    }
    if (linear <= 0 || !std::isfinite(linear)) linear = 0.1;
}

} // namespace

extern "C" int p3d_cad_load(const char *path, int quality, size_t budget,
                            P3DStepMesh *out) {
    if (!out) return 1;
    out->corners = nullptr;
    out->cornerCount = 0;
    out->faceCount = 0;
    out->error = nullptr;

    if (!path) {
        out->error = duplicate("no file path given");
        return 1;
    }
    silenceOCCT();

    TopoDS_Shape shape;
    try {
        const std::string file(path);
        IFSelect_ReturnStatus status;

        // The two readers share the XSControl machinery but not a base class;
        // factoring them together would mean going through the generic
        // interface, which is markedly more verbose.
        if (isIGES(file)) {
            IGESControl_Reader reader;
            status = reader.ReadFile(path);
            if (status != IFSelect_RetDone) {
                out->error = duplicate("IGES file could not be read");
                return 1;
            }
            reader.TransferRoots();
            shape = reader.OneShape();
        } else {
            STEPControl_Reader reader;
            status = reader.ReadFile(path);
            if (status != IFSelect_RetDone) {
                out->error = duplicate("STEP file could not be read");
                return 1;
            }
            const Standard_Integer roots = reader.NbRootsForTransfer();
            if (roots <= 0) {
                out->error = duplicate("STEP file contains no transferable entity");
                return 1;
            }
            reader.TransferRoots();
            shape = reader.OneShape();
        }
    } catch (const Standard_Failure &e) {
        out->error = duplicate(std::string("OpenCASCADE: ") +
                               (e.GetMessageString() ? e.GetMessageString() : "read failed"));
        return 1;
    } catch (...) {
        out->error = duplicate("unknown failure while reading the file");
        return 1;
    }

    if (shape.IsNull()) {
        out->error = duplicate("the file yielded an empty shape");
        return 1;
    }

    std::vector<float> corners;
    size_t faceCount = 0;

    try {
        Bnd_Box box;
        BRepBndLib::Add(shape, box);
        double diagonal = 1.0;
        if (!box.IsVoid()) {
            double xa, ya, za, xb, yb, zb;
            box.Get(xa, ya, za, xb, yb, zb);
            const double dx = xb - xa, dy = yb - ya, dz = zb - za;
            diagonal = std::sqrt(dx * dx + dy * dy + dz * dz);
            if (!std::isfinite(diagonal) || diagonal <= 0) diagonal = 1.0;
        }

        double linear, angular;
        meshingParameters(quality, diagonal, linear, angular);

        // isRelative=false: deflection is already scaled to the part, and
        // leaving it relative to each edge would give a mesh that is very uneven
        // between large flats and small fillets.
        BRepMesh_IncrementalMesh mesher(shape, linear, Standard_False, angular, Standard_True);
        mesher.Perform();

        corners.reserve(std::min<size_t>(budget, 3 * 1024 * 1024));

        for (TopExp_Explorer it(shape, TopAbs_FACE); it.More(); it.Next()) {
            const TopoDS_Face face = TopoDS::Face(it.Current());
            TopLoc_Location location;
            const Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, location);
            if (tri.IsNull()) continue;
            faceCount++;

            const gp_Trsf &transform = location.Transformation();
            // A reversed face lists its triangles clockwise, so two vertices
            // have to be swapped for the normal computed later to point out.
            const bool reversed = (face.Orientation() == TopAbs_REVERSED);

            for (Standard_Integer i = 1; i <= tri->NbTriangles(); ++i) {
                Standard_Integer a, b, c;
                tri->Triangle(i).Get(a, b, c);
                if (reversed) std::swap(b, c);

                const Standard_Integer slots[3] = {a, b, c};
                for (int k = 0; k < 3; ++k) {
                    gp_Pnt p = tri->Node(slots[k]);
                    if (!location.IsIdentity()) p.Transform(transform);
                    corners.push_back(static_cast<float>(p.X()));
                    corners.push_back(static_cast<float>(p.Y()));
                    corners.push_back(static_cast<float>(p.Z()));
                }
            }

            if (corners.size() / 3 >= budget) break;
        }
    } catch (const Standard_Failure &e) {
        out->error = duplicate(std::string("OpenCASCADE: ") +
                               (e.GetMessageString() ? e.GetMessageString() : "meshing failed"));
        return 1;
    } catch (...) {
        out->error = duplicate("unknown failure while meshing the shape");
        return 1;
    }

    if (corners.empty()) {
        out->error = duplicate("the model has no surface that could be meshed");
        return 1;
    }

    float *buffer = static_cast<float *>(std::malloc(corners.size() * sizeof(float)));
    if (!buffer) {
        out->error = duplicate("out of memory");
        return 1;
    }
    std::memcpy(buffer, corners.data(), corners.size() * sizeof(float));
    out->corners = buffer;
    out->cornerCount = corners.size() / 3;
    out->faceCount = faceCount;
    return 0;
}

extern "C" void p3d_mesh_free(P3DStepMesh *mesh) {
    if (!mesh) return;
    std::free(mesh->corners);
    std::free(mesh->error);
    mesh->corners = nullptr;
    mesh->error = nullptr;
    mesh->cornerCount = 0;
}

extern "C" const char *p3d_occt_version(void) {
    return OCC_VERSION_COMPLETE;
}
