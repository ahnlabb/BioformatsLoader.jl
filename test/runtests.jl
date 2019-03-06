using BioformatsLoader
using Test

BioformatsLoader.init()

oxr = OMEXMLReader()
@test oxr.reader.ptr != C_NULL
@test oxr.meta.ptr != C_NULL
