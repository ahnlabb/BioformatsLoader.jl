using BioformatsLoader
using Test
using JavaCall
import Pkg

pkg_path = dirname(dirname(pathof(BioformatsLoader)))
bfpkg_path = joinpath(pkg_path, "jars/bioformats_package.jar")

println(bfpkg_path)
download("https://downloads.openmicroscopy.org/bio-formats/5.7.3/artifacts/bioformats_package.jar", bfpkg_path)

JavaCall.init(["-verbose:gc","-Djava.class.path=$bfpkg_path"])

oxr = OMEXMLReader()
@test oxr.reader.ptr != C_NULL
@test oxr.meta.ptr != C_NULL
