using BioformatsLoader
using Base.Test
using JavaCall

pkgname = "BioformatsLoader"
bfpkg_path = joinpath(Pkg.dir(), pkgname, "bioformats_package.jar")

download("https://downloads.openmicroscopy.org/bio-formats/5.7.3/artifacts/bioformats_package.jar", bfpkg_path)

JavaCall.init(["-verbose:gc","-Djava.class.path=$bfpkg_path"])

oxr = OMEXMLReader()
@test oxr.reader.ptr != C_NULL
@test oxr.meta.ptr != C_NULL
