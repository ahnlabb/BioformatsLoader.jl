using BioformatsLoader
using JavaCall
using Test

@test BioformatsLoader.init() == nothing

oxr = OMEXMLReader()
@test !JavaCall.isnull(oxr.reader)
@test !JavaCall.isnull(oxr.meta)

nd2_file = bf_import(joinpath(@__DIR__,"test_format.nd2"))
czi_file = bf_import(joinpath(@__DIR__,"test_zen.CZI"))

@test size(nd2_file) == (1,)
