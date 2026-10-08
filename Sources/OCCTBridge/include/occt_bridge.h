// A C interface over OpenCASCADE.
//
// Swift can call C, not C++ with its exceptions and reference-counted handles.
// The whole of the CAD kernel therefore stays behind these three functions, and
// no exception ever crosses this boundary.
#ifndef OCCT_BRIDGE_H
#define OCCT_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    /// Three floats per vertex, three consecutive vertices per triangle.
    float  *corners;
    size_t  cornerCount;
    /// How many B-Rep faces were actually tessellated, for information.
    size_t  faceCount;
    /// Message from OpenCASCADE, or NULL when everything went well.
    char   *error;
} P3DStepMesh;

/// Reads a STEP or IGES file and turns it into triangles.
///
/// `quality` sets the fineness: 0 for a thumbnail, 1 for a preview, 2 for a
/// careful render. `budget` caps the number of vertices produced; past it,
/// tessellation stops and returns what it already has, so that a very heavy
/// part cannot stall an extension working against a deadline.
///
/// Returns 0 on success. The caller must always call p3d_mesh_free.
int p3d_cad_load(const char *path, int quality, size_t budget, P3DStepMesh *out);

void p3d_mesh_free(P3DStepMesh *mesh);

/// The embedded OpenCASCADE version, for the About panel.
const char *p3d_occt_version(void);

#ifdef __cplusplus
}
#endif
#endif
