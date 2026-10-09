# Third-party software

Peek3D is MIT licensed. It ships with the following inside its bundle.

## OpenCASCADE Technology

Reads STEP and IGES: these formats describe exact surfaces, and turning them
into triangles is the work of a geometry kernel.

- Licence: LGPL 2.1, with the OCCT exception
- https://dev.opencascade.org/resources/licensing

The OCCT exception permits linking and redistribution inside an application
under a different licence, provided the notice is kept and the libraries stay
replaceable. They ship as separate dynamic libraries in
`Peek3D.app/Contents/Frameworks`, so they are.

Build them from source with `scripts/build-occt.sh`.
