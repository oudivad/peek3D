// Builds Tests/fixtures/manifold.step — the worst case for a preview.
//
// The simple fixtures prove the loaders work; they prove nothing about what a
// dense mesh looks like. This part is built to be awkward: a bolt circle, a
// bored boss, ribs, and a fillet on every intersection. Fillets are what makes
// a tessellation heavy — each one becomes a band of long thin triangles — so a
// part covered in them is where "all triangles" turns into a smear and "sharp
// edges" earns its place.
//
// Kept as source rather than committing an opaque file with nothing to explain
// where it came from:
//
//   clang++ -std=c++17 -O1 -o /tmp/make-fixture scripts/make-fixture.cpp \
//       -I vendor/occt/include/opencascade -L vendor/occt/lib \
//       $(ls vendor/occt/lib/libTK*.dylib | grep -v '7\.9' \
//         | sed 's|.*/lib|-l|;s|\.dylib||' | tr '\n' ' ') \
//       -Wl,-rpath,$PWD/vendor/occt/lib
//   /tmp/make-fixture Tests/fixtures/manifold.step
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepFilletAPI_MakeChamfer.hxx>
#include <STEPControl_Writer.hxx>
#include <TopExp_Explorer.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <BRepAdaptor_Curve.hxx>
#include <TopoDS.hxx>
#include <gp_Ax2.hxx>
#include <cmath>
#include <cstdio>

static TopoDS_Shape bore(const TopoDS_Shape& in, double x, double y, double r) {
    return BRepAlgoAPI_Cut(in, BRepPrimAPI_MakeCylinder(
        gp_Ax2(gp_Pnt(x, y, -5), gp_Dir(0, 0, 1)), r, 40).Shape()).Shape();
}

int main(int argc, char** argv) {
    if (argc < 2) { std::fprintf(stderr, "usage: make-fixture <out.step>\n"); return 2; }

    TopoDS_Shape part = BRepPrimAPI_MakeBox(gp_Pnt(0, 0, 0), 140, 90, 12).Shape();

    // A bored boss standing on the plate.
    part = BRepAlgoAPI_Fuse(part, BRepPrimAPI_MakeCylinder(
        gp_Ax2(gp_Pnt(70, 45, 12), gp_Dir(0, 0, 1)), 26, 22).Shape()).Shape();

    // Two ribs bracing it.
    for (double y : {24.0, 60.0}) {
        part = BRepAlgoAPI_Fuse(part, BRepPrimAPI_MakeBox(
            gp_Pnt(62, y, 12), 16, 6, 16).Shape()).Shape();
    }

    // Fillet the junctions — before drilling, so the holes keep sharp rims.
    // A part filleted everywhere, rims included, has no sharp edge left at all,
    // which is neither how parts are made nor a useful thing to look at.
    TopTools_IndexedMapOfShape edges;
    TopExp::MapShapes(part, TopAbs_EDGE, edges);
    for (int i = 1; i <= edges.Extent(); ++i) {
        BRepFilletAPI_MakeFillet fillet(part);
        fillet.Add(3.0, TopoDS::Edge(edges(i)));
        try {
            fillet.Build();
            if (fillet.IsDone()) part = fillet.Shape();
        } catch (...) {}
    }

    part = bore(part, 70, 45, 14);                      // central bore

    // An annular groove around the boss: two concentric cylinders, so four
    // more curved walls and four more sharp rims.
    part = BRepAlgoAPI_Cut(part, BRepAlgoAPI_Cut(
        BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(70, 45, 28), gp_Dir(0, 0, 1)), 23, 10).Shape(),
        BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(70, 45, 28), gp_Dir(0, 0, 1)), 19, 10).Shape()
    ).Shape()).Shape();

    // Sixteen counterbored bolt holes. Every counterbore is a second cylinder
    // and two more rims: this is what makes a tessellation heavy while leaving
    // plenty of genuinely sharp edges to find.
    for (int i = 0; i < 16; ++i) {
        const double a = i * M_PI / 8;
        const double x = 70 + 40 * std::cos(a), y = 45 + 40 * std::sin(a);
        part = bore(part, x, y, 3.2);
        part = BRepAlgoAPI_Cut(part, BRepPrimAPI_MakeCylinder(
            gp_Ax2(gp_Pnt(x, y, 6), gp_Dir(0, 0, 1)), 6, 40).Shape()).Shape();
    }
    for (double x : {10.0, 130.0}) {                    // corner fixings
        for (double y : {10.0, 80.0}) part = bore(part, x, y, 5);
    }

    // Knurling around the boss: forty-eight small flutes. Fine features on a
    // large part are what drive a tessellation up, because the deflection is
    // relative to the whole and every flute still has to be rounded.
    for (int i = 0; i < 48; ++i) {
        const double a = i * M_PI / 24;
        part = BRepAlgoAPI_Cut(part, BRepPrimAPI_MakeCylinder(
            gp_Ax2(gp_Pnt(70 + 26 * std::cos(a), 45 + 26 * std::sin(a), 12),
                   gp_Dir(0, 0, 1)), 1.6, 22).Shape()).Shape();
    }

    STEPControl_Writer writer;
    writer.Transfer(part, STEPControl_AsIs);
    if (writer.Write(argv[1]) != IFSelect_RetDone) return 1;

    TopTools_IndexedMapOfShape faces;
    TopExp::MapShapes(part, TopAbs_FACE, faces);
    std::printf("%d faces\n", faces.Extent());
    return 0;
}
