using BioformatsLoader
using Test
using JavaCall
import Pkg

BioformatsLoader.init()

oxr = OMEXMLReader()
@test oxr.reader.ptr != C_NULL
@test oxr.meta.ptr != C_NULL
