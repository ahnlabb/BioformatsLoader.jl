using BioformatsLoader
using JavaCall
using Test
using Downloads
using AxisArrays

@test BioformatsLoader.init() == nothing

oxr = OMEXMLReader()
@test !JavaCall.isnull(oxr.reader)
@test !JavaCall.isnull(oxr.meta)

ome_imgs_url = "https://downloads.openmicroscopy.org/images/"

ome_paths =
    Dict(
        "ND2" => [
            "maxime/BF007.nd2",
            "aryeh/MeOh_high_fluo_003.nd2"
        ],
    )

test_slice = (Axis{:T}(1), Axis{:Z}(1), Axis{:C}(1), Axis{:X}(1), Axis{:Y}(:))
for (fmt, paths) in ome_paths
    for p in paths
        url = joinpath(ome_imgs_url, fmt, p)
        imgs = bf_import(url)
        @test length(imgs) > 0

        filename = basename(p)

        mktempdir() do path
            imgpath = joinpath(path, filename)
            Downloads.download(url, imgpath)
            for (order, import_order) in [("TZYXC", (:T, :Z, :Y, :X, :C)),
                                          ("XYCZT", (:X, :Y, :C, :Z, :T))]
                img = bf_import(imgpath; order)[1]
                @test img.ImportOrder == import_order
                @test arraydata(img[test_slice...]) == arraydata(imgs[1][test_slice...])
            end
        end
    end
end
