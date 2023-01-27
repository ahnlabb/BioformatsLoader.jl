module BioformatsLoader
using JavaCall
import JavaCall.JNI
using LightXML
using ImageMetadata
using AxisArrays
using URIs
using ImageCore
using Downloads
using Logging

export
    set_id!,
    OMEXMLReader,
    openbytes,
    open_reinterpret,
    set_series!,
    getpixeltype,
    open_img,
    bf_import,
    open_stack,
    metadata,
    arraydata,
    axisnames,
    get_num_sets,
    get_RGB_channel_count

include("metadata.jl")
include("omexmlreader.jl")

struct Stack{T}
    bfr
    series::Int
end

struct BFReader{T} <: AbstractVector{Stack{T}}
    oxr::OMEXMLReader
    metalst
    order
end

function BFReader{T}(oxr::OMEXMLReader; order="CYXZT") where T
    xml = get_xml(oxr)
    metalst = get_elements_by_tagname(root(xml), "Image")
    BFReader{T}(oxr, metalst, order)
end


normtype(::Type{T}) where T <: AbstractFloat = T
normtype(::Type{T}) where T <: Unsigned = Normed{T, sizeof(T)*8}
normtype(::Type{Bool}) = Bool

function BFReader(oxr::OMEXMLReader; colorant=nothing, kwargs...)
    pxtype = getpixeltype(oxr)
    if !isnothing(colorant)
        pxtype = colorant{normtype(pxtype)}
    end
    BFReader{pxtype}(oxr; kwargs...)
end

with_oxr(f, T, args...; kwargs...) = OMEXMLReader(oxr -> f(T(oxr; kwargs...)), args...)
BFReader{T}(filename) where T = BFReader{T}(OMEXMLReader(filename))
BFReader{T}(fun::Function, filename; kwargs...) where T = with_oxr(fun, BFReader{T}, filename)
BFReader(fun::Function, filename; kwargs...) =  with_oxr(fun, BFReader, filename; kwargs...)

Base.size(bfr::BFReader, args...) = size(bfr.metalst, args...)
function Base.getindex(bfr::BFReader{T}, i::Int) where T
    Stack{T}(bfr, i)
end


_convert(T, x) = convert(T, x)
_convert(::Type{<:Normed{T}}, x::T) where T = reinterpret(Normed{T, 8sizeof(T)}, x)
_convert(c::Type{<:Color{C,1}}, x::T) where {C, T} = c(_convert(C, x))
Base.convert(::Type{AxisArray{T}}, arr::A) where {T, A <: AxisArray{T}} = arr
Base.convert(::Type{AxisArray{T}}, arr::A) where {T, A <: AxisArray} = map(x -> _convert(T, x), arr)

function Base.getindex(stack::Stack{T}, inds...) where T
    set_series!(stack.bfr.oxr, stack.series)
    img = open_stack(stack.bfr.oxr; subidx=inds, order=stack.bfr.order)
    properties = xml_to_dict(stack.bfr.metalst[stack.series])
    properties[:ImportOrder] = axisnames(img)
    ImageMeta(convert(AxisArray{T}, img), properties)
end
Base.getindex(stack::Stack) = stack[:,:,:,:,:]

const scheme2importer = Dict{String, Any}()

function add_importer(importer, schemes)
    for s in schemes
        scheme2importer[s] = importer
    end
end

function open_img(oxr::OMEXMLReader, index::Int)
    sx = get_size(oxr, "X")
    sy = get_size(oxr, "Y")
    arr = openbytes(oxr, index)
    return interpret_blob!(oxr, arr, (sx, sy))
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
    OMEXMLReader(open_stack, filename)
end

function interpret_blob!(oxr, arr, sizes)
    arr = reinterpret(getpixeltype(oxr), arr)
    if !islittleendian(oxr)
        @. arr = ntoh(arr)
    end
    return reshape(arr, sizes)
end

function no_colon(sz, subidx)
    ntuple((d)->typeof(subidx[d]) == Colon ? (1:sz[d]) : 
            ((typeof(subidx[d]) <: Number) ? (subidx[d]:subidx[d]) : subidx[d]), length(sz))
end

function sub_indices(sz, subidx)
    CartesianIndices(no_colon(sz, subidx))
end

function clipped_size(sz, subidx)
    return size(sub_indices(sz, subidx))
end


function open_stack(oxr::OMEXMLReader; subidx=nothing, order="CYXZT")
    image_order = get_dimension_order(oxr)
    if isinterleaved(oxr)
        image_order = replace(image_order, "XYC" => "CXY")
    end

    sizes = [get_size(oxr, d) for d in image_order]
    size_dict = Dict(zip(image_order, sizes))

    for d in image_order
        if !in(d, order)
            @assert (size_dict[d] == 1) "Non-singleton dimension \"$d\" is not present in the requested image order \"$order\""
        end
    end

    num_imgs = get_image_count(oxr)
    trail_size=1;
    trail_dim=length(image_order)
    for d=length(image_order):-1:1
        trail_size *= size_dict[image_order[d]]
        if trail_size == num_imgs
            trail_dim = d
            break
        elseif trail_size > num_imgs
            error("size inconsistency")
        end
    end
    raw_size = Tuple(size_dict[d] for d in image_order if in(d, order))

    subidx = let
        if isnothing(subidx)
            (:,:,:,:,:) # 0:(num_imgs - 1)
        else
            sub_dict = Dict(zip(order, subidx))
            Tuple(sub_dict[d] for d in image_order if in(d, order))
        end
    end
    fsubidx = subidx[1:trail_dim-1]
    tsubidx = subidx[trail_dim:end]

    all_idx = sub_indices(raw_size[trail_dim:end], tsubidx)
    LI = LinearIndices(raw_size[trail_dim:end])
    arr = open_reinterpret(oxr, LI[all_idx[1]]-1, fsubidx, raw_size[1:trail_dim-1])
    for ci in all_idx[2:end]
        idx = LI[ci]
        arr_nd = open_reinterpret(oxr, idx-1, fsubidx, raw_size[1:trail_dim-1])
        append!(arr, arr_nd)
    end
    new_raw_size = clipped_size(raw_size, subidx)
    im = interpret_blob!(oxr, arr, (new_raw_size...,))
    im = permutedims(im, [findfirst(c, image_order) for c in order])

    return AxisArray(im, (Symbol(d) for d in order)...)
end

"""
    bf_import(uri::AbstractString; order::AbstractString="TZYXC", squeeze::Bool=false, subset=nothing, subidx=nothing)

Import all images and metadata in the file using Bio-Formats.

The `order` keyword argument is the output order of dimensions, allowing you to
reshuffle the dimensions of the images or skip singleton dimensions. Providing
"CYX" for `order` gives you three-dimensional images in a "channels-first" data
format but will fail with an error if any of the images in the file has a size
greater than one in the `T` or `Z` dimension.

By setting the `squeeze` keyword argument to `true` all singleton dimensions in
the images will be dropped (even if they are in the `order` argument).

The keyword argument `subset` allows to only import one or multiple specific sets (for datasets with multiple sets)
and the keyword argument `subidx` allows to import specific ranges of the data (in the `order` as given by the user).
"""
function bf_import(uri; kwargs...)
    u = URI(uri)
    if u.scheme in keys(scheme2importer)
        scheme2importer[u.scheme](u; kwargs...)
    else
        if length(u.scheme) > 1
            @warn "Unrecognized scheme \"$(u.scheme)\", attempting to open as file"
        end
        bf_import_file(uri; kwargs...)
    end
end

"""
    get_num_sets(filename::AbstractString)

returns the number of series present in the file as given by `filename`. Currently URLs are not allowed to avoid multiple downloads. 
"""
get_num_sets(filename::AbstractString) = length(BFReader(filename))

bf_import_file(uri::URI; kwargs...) = bf_import_file(uri.path; kwargs...)
function bf_import_file(filename::AbstractString; subset=nothing, subidx=nothing, order="CYXZT", squeeze=false, gray=false)
    BFReader(filename; order, colorant=gray ? Gray : nothing) do bfr
        subset = isnothing(subset) ? Colon() : subset
        subidx = isnothing(subidx) ? (:,:,:,:,:) : subidx
        map(bfr[subset]) do stack
            imgmeta = stack[subidx...]
            if squeeze
                img = dropdims(arraydata(imgmeta); dims=((i for i in 1:ndims(img) if size(img, i) == 1)...,))
                ImageMeta(img, properties(imgmeta))
            else
                imgmeta
            end
        end
    end
end

add_importer(bf_import_file, ["file"])

"""
    bf_import_http(url::AbstractString, [ filename::AbstractString ]; kwargs...)

Download and import an image using Bio-Formats.
"""
bf_import_http(url::AbstractString, args...; kwargs...) = bf_import_http(URI(url), args...; kwargs...)

function bf_import_http(url::URI; kwargs...)
    filename = basename(url.path)
    @assert (filename != "") "Could not determine filename from URL"
    bf_import_http(url, filename; kwargs...)
end

function bf_import_http(url::URI, filename::AbstractString; kwargs...)
    mktempdir() do path
        imgpath = joinpath(path, filename)
        Downloads.download(string(url), imgpath)
        bf_import_file(imgpath; kwargs...)
    end
end

add_importer(bf_import_http, ["http", "https"])

function metadata(filename::String)
    OMEXMLReader(filename) do oxr
        xml = get_xml(oxr)
        properties = Dict{String, Any}()
        metalst = get_elements_by_tagname(root(xml), "Image")

        SizeC = get_size(oxr, "C")

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

        if length(metalst[1]["Pixels"][1]["Channel"]) == SizeC
            for i in 1:SizeC
                for a in attributes(metalst[1]["Pixels"][1]["Channel"][i])
                    if name(a)== "EmissionWavelength"
                        push!(properties, "channel_$i"=>value(a))
                    end
                end
            end
        end
        properties
    end
end

const levels = ["ALL", "DEBUG", "ERROR", "FATAL", "INFO", "OFF", "TRACE", "WARN"]
function enableLogging(level::String)
    level in levels || error("enableLogging: level argument must be one of "*join(levels,", "))
    dt = @jimport(loci.common.DebugTools)
    Bool(jcall(dt,"enableLogging",jboolean,(JString,),level))
end

get_bf_path() = joinpath(dirname(@__DIR__), "deps", "bioformats_package.jar")

function set_memory(memory=1024)
    if memory > 0
        # There should be a distinct memory option in JavaCall
        # Find other memory options and delete them
        filter!(opt -> !startswith(opt, "-Xmx"), JavaCall.opts)
        # Add a new option as specified
        JavaCall.addOpts("-Xmx$(memory)M")
    end
    nothing
end

function __init__()
    # Configure JavaCall and JVM
    bfpkg_path = get_bf_path()
    JavaCall.addOpts("-ea")
    JavaCall.addOpts("-Xrs")
    set_memory()
    JavaCall.addClassPath(bfpkg_path)
end

let initialized = Ref(false)
    global init, ensure_init
    function init(;memory::Int=-1, log_level::String="ERROR")
        if !initialized[]
            if !JavaCall.isloaded()
                set_memory(memory)
                JavaCall.init()
                atexit(JavaCall.destroy)
            else
                @warn "JavaCall already initialized"
            end
            initialized[] = true
            enableLogging(log_level) || @warn "Could not enable logging."
        else
            @warn "BioformatsLoader already initialized"
        end
        nothing
    end
    ensure_init() = initialized[] ? nothing : init()
end

end
