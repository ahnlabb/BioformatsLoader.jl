module BioformatsLoader
using JavaCall
using LightXML
using ImageMetadata
using ImageCore

export
    set_id!,
    OMEXMLReader,
    openbytes,
    set_series!,
    getpixeltype,
    open_img,
    bf_import,
    open_stack,
    metadata,
    arraydata


include("metadata.jl")
include("omexmlreader.jl")

function open_img(oxr::OMEXMLReader, index::Int)
    sx = get_size(oxr, "X")
    sy = get_size(oxr, "Y")
    arr = reinterpret(getpixeltype(oxr), openbytes(oxr, index))
    if islittleendian == 0
        @. arr = ntoh(arr)
    end
    return reshape(arr, (sx, sy))
end

for F in (:open_stack, :bf_import, :metadata)
    @eval begin
        function $F(filename::String, redirect::IO)
            redirect_stdout(() -> $F(filename), redirect)
        end
        function $F(filename::String, show_output::Bool)
            if show_output
                $F(filename)
            else
                STDOLD = stdout
                local ret
                redirect_stdout()
                try
                    ret = $F(filename)
                finally
                    redirect_stdout(STDOLD)
                end
                ret
            end
        end
    end
end

function open_stack(filename::String)
    oxr = OMEXMLReader(filename)
    return open_stack(oxr)
end

function open_stack(oxr::OMEXMLReader; order="TZYXC")
    image_order = get_dimension_order(oxr)
    sizes = [get_size(oxr, d) for d in image_order]
    size_dict = Dict(zip(image_order, sizes))

    for d in image_order
        if !in(d, order)
            @assert (size_dict[d] == 1) "Non-singleton dimension \"$d\" is not present in the requested image order \"$order\""
        end
    end

    arr = openbytes(oxr, 0)

    for i in 1:(get_image_count(oxr) - 1)
        arr_nd = openbytes(oxr, i)
        append!(arr,arr_nd)
    end

    if islittleendian == 0
        @. arr = ntoh(arr)
    end
    arr = reinterpret(getpixeltype(oxr), arr)

    im = reshape(arr, ((size_dict[d] for d in image_order if in(d, order))...,))
    im = permutedims(im, [findfirst(c, image_order) for c in order])

    return im
end

"""
    bf_import(filename::String; order::String="TZYXC", squeeze::Bool=false)

Import all images and metadata in the file using Bio-Formats.

The `order` keyword argument is the output order of dimensions, allowing you to
reshuffle the dimensions of the images or skip singleton dimensions. Providing
"CYX" for `order` gives you three-dimensional images in a "channels-first" data
format but will fail with an error if any of the images in the file has a size
greater than one in the `T` or `Z` dimension.

By setting the `squeeze` keyword argument to `true` all singleton dimensions in
the images will be dropped (even if they are in the `order` argument).
"""
function bf_import(filename::String; order="TZYXC", squeeze=false, gray=false)
    oxr = OMEXMLReader(filename)
    xml = get_xml(oxr)
    images = Array{ImageMeta,1}()

    metalst = get_elements_by_tagname(root(xml), "Image")
    for i = 1:length(metalst)
        set_series!(oxr, i-1)
        img = open_stack(oxr; order = order)
        if squeeze
            img = dropdims(img; dims=((i for i in 1:ndims(img) if size(img, i) == 1)...,))
        end
        if gray
            img = as_gray(img)
        end
        properties = xml_to_dict(metalst[i])
        push!(images, ImageMeta(img, properties))
    end

    return images
end

function as_gray(arr::A) where A <: AbstractArray{T} where T <: Unsigned
    Gray.(reinterpret.(Normed{T, sizeof(T)*8}, arr))
end
function as_gray(arr::A) where A <: AbstractArray{T} where T <: AbstractFloat
    Gray.(arr)
end
function as_gray(arr::A) where A <: AbstractArray{Bool}
    Gray.(arr)
end

function metadata(filename::String)
    oxr = OMEXMLReader(filename)
    xml = get_xml(oxr)
    properties = Dict{String, Any}()
    metalst = get_elements_by_tagname(root(xml), "Image")

    SizeC = get_size(oxr.reader, "C")

    for a = attributes(metalst[1])
        push!(properties, "$(name(a))"=>value(a))
    end
    for a = attributes(find_element(metalst[1], "Pixels"))
        try
            push!(properties, "$(name(a))"=> parse(Float64, value(a)))
        catch ex
            if ex isa ArgumentError
                push!(properties, "$(name(a))"=>  value(a))
            end
        end
    end

    for i in 1:SizeC
        for a in attributes(metalst[1]["Pixels"][1]["Channel"][i])
            if name(a)== "EmissionWavelength"
                push!(properties, "channel_$i"=>value(a))
            end
        end
    end
end

const levels = ["ALL", "DEBUG", "ERROR", "FATAL", "INFO", "OFF", "TRACE", "WARN"]
function enableLogging(level::String)
    level in levels || error("enableLogging: level argument must be one of "*join(levels,", "))
    dt = @jimport(loci.common.DebugTools)
    Bool(jcall(dt,"enableLogging",jboolean,(JString,),level))
end

get_bf_path() = joinpath(dirname(@__DIR__), "deps", "bioformats_package.jar")

function init(;memory=1024::Int,log_level::String="ERROR")
    bfpkg_path = get_bf_path()
    JavaCall.init(["-ea", "-Xmx$(memory)M", "-Djava.class.path=$bfpkg_path"])
    enableLogging(log_level) || @warn "Could not enable logging."
    nothing
end

end
