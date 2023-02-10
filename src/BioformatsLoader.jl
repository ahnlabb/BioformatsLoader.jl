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
include("bfreader.jl")

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
	return reshape(interpret_blob!(oxr, arr), (sx, sy))
end

for F in (:open_stack, :bf_import, :metadata)
    @eval begin
        function $F(filename::String, redirect::IO)
            redirect_stdout(() -> $F(filename), redirect)
        end
        function $F(filename::String, show_output::Bool)
            show_output ? $F(filename) : $F(filename, devnull)
        end
    end
end

function interpret_blob!(oxr, arr)
    arr = reinterpret(getpixeltype(oxr), arr)
    if !islittleendian(oxr)
        @. arr = ntoh(arr)
    end
    return arr
end

no_colon(sz, idx) = idx
no_colon(sz, idx::Colon) = 1:sz
no_colon(sz, subidx::Tuple) = ntuple(d -> no_colon(sz[d], subidx[d]), length(sz))

function sub_indices(sz, subidx)
    CartesianIndices(no_colon(sz, subidx))
end

function clipped_size(sz, subidx)
    return size(sub_indices(sz, subidx))
end


open_stack(filename::String) = OMEXMLReader(open_stack, filename)

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
    trail_size = 1
    trail_dim = length(image_order)
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

	java_idx = let all_idx = sub_indices(raw_size[trail_dim:end], tsubidx)
		li = LinearIndices(raw_size[trail_dim:end])
		map(i -> li[i] - 1, all_idx)
	end

    new_raw_size = clipped_size(raw_size, subidx)

	arr = Array{getpixeltype(oxr)}(undef, new_raw_size...)
	f = if all(iscolon, fsubidx)
		i -> interpret_blob!(oxr, openbytes(oxr, i))
    else
        x, y, w, h, new_range = get_xywh(fsubidx, raw_size[1:trail_dim-1])
		get_interpreted(i) = interpret_blob!(oxr, openbytes(oxr, i, x, y, w, h))

		if all(iscolon, new_range)
			get_interpreted
        else
			i -> reshape(get_interpreted(i), (w,h))[new_range...]
        end
	end
	chunk_filled!(f, arr, java_idx)

    img = permutedims(arr, [findfirst(c, image_order) for c in order])

    return AxisArray(img, (Symbol(d) for d in order)...)
end

iscolon(x) = x isa Colon

chunk_filled!(f, arr, itr::T) where {T} = chunk_filled!(f, arr, Iterators.IteratorSize(T), itr)
function chunk_filled!(f, arr, ::T, itr) where {T <: Union{Iterators.HasShape, Iterators.HasLength}}
	chunk_size = fld(length(arr), length(itr))
	for (i, x) in enumerate(itr)
		arr[(i-1)*chunk_size+1:i*chunk_size] .= view(f(x), :)
	end
	return arr
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
get_num_sets(filename::AbstractString) = BFReader(length, filename)

mapindex(f, arr, index) = map(f, arr[index])
mapindex(f, arr, index::Number) = f(arr[index])
bf_import_file(uri::URI; kwargs...) = bf_import_file(uri.path; kwargs...)
function bf_import_file(filename::AbstractString; subset=Colon(), subidx=(:,:,:,:,:), order="CYXZT", squeeze=false, gray=false)
    BFReader(filename; order, colorant=gray ? Gray : nothing) do bfr
        mapindex(bfr, subset) do stack
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

metadata(filename::String) = BFReader(metadata, filename)
metadata(bfr::BFReader) = metadata(bfr[1])

_attribute_pairs(x::XMLElement) = (string(name(a)) => value(a) for a in attributes(x))

function metadata(stack::Stack)
	meta = stack.bfr.metalst[stack.series]
	pixels = meta["Pixels"][1]
	[
		_attribute_pairs(meta),
		Iterators.map(_attribute_pairs(pixels)) do (k, val)
			parsed = tryparse(Float64, val)
			k => (parsed === nothing ? val : parsed)
		end,
		Iterators.map(Iterators.enumerate(pixels["Channel"])) do (i, e)
			val = attribute(e, "EmissionWavelength"; required=false)
			"channel_$i"=>val
		end
	] |> Iterators.flatten |> Dict
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
