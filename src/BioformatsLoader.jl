module BioformatsLoader
using JavaCall
using LightXML
using ImageMetadata

export
    set_id,
    OMEXMLReader,
    openbytes,
    set_series,
    getpixeltype,
    open_img,
    bf_import,
    open_stack,
    metadata,
    arraydata


include("metadata.jl")

const JServiceFactory = @jimport loci.common.services.ServiceFactory
const JService = @jimport loci.common.services.Service
const JIFormatReader = @jimport loci.formats.IFormatReader
const JImageReader = @jimport loci.formats.ImageReader
const JOMEXMLMetadata = @jimport loci.formats.ome.OMEXMLMetadata
const JMetadataStore = @jimport loci.formats.meta.MetadataStore

const datatypes = [Int8,UInt8,Int16,UInt16,Int32,UInt32,Float32,Float64,Bool]

function create_service(classname::String)
    factory = JServiceFactory(())
    cls = classforname(classname)
    service = jcall(factory, "getInstance", JService, (JClass,), cls)
    return convert(JavaObject{Symbol(classname)}, service)
end

struct OMEXMLReader
    reader::JavaObject
    meta::JavaObject
end

function OMEXMLReader()
    service = create_service("loci.formats.services.OMEXMLService")
    meta = jcall(service, "createOMEXMLMetadata", JOMEXMLMetadata, ())
    reader = convert(JIFormatReader, JImageReader(()))

    jcall(reader, "setMetadataStore", Nothing, (JMetadataStore,), meta)
    OMEXMLReader(reader, meta)
end


function set_id(oxr::OMEXMLReader, fname::AbstractString)
    jcall(oxr.reader, "setId", Nothing, (JString,), string(fname))
end

function openbytes(oxr::OMEXMLReader, index::Int)
    jcall(oxr.reader, "openBytes", Vector{jbyte}, (jint,), index)
end

function set_series(oxr::OMEXMLReader, index::Int)
    jcall(oxr.reader, "setSeries", Nothing, (jint,), index)
end

function getpixeltype(oxr::OMEXMLReader)
    id = jcall(oxr.reader, "getPixelType", jint, ())
    return datatypes[id+1]
end

function islittleendian(oxr::OMEXMLReader)
    jcall(oxr.reader, "isLittleEndian", jboolean, ())
end

function open_img(oxr::OMEXMLReader, index::Int)
    sx = jcall(oxr.reader, "getSizeX", jint, ())
    sy = jcall(oxr.reader, "getSizeY", jint, ())
    arr = reinterpret(getpixeltype(oxr), openbytes(oxr, index))
    if islittleendian == 0
        @. arr = ntoh(arr)
    end
    return reshape(arr, (sx, sy))
end

for F in (:open_stack, :bf_import, :metadata)
    @eval begin
        function $F(fname::String, redirect::IO)
            redirect_stdout(() -> $F(fname), redirect)
        end
        function $F(fname::String, show_output::Bool)
            if show_output
                $F(fname)
            else
                STDOLD = stdout
                local ret
                redirect_stdout()
                try
                    ret = $F(fname)
                finally
                    redirect_stdout(STDOLD)
                end
                ret
            end
        end
    end
end

function open_stack(fname::String)
    oxr = OMEXMLReader()
    set_id(oxr, fname)
    return open_stack(oxr)
end

function open_stack(oxr::OMEXMLReader; order="TZYXC")
    image_order = jcall(oxr.reader, "getDimensionOrder", JString, ())
    sizes = [jcall(oxr.reader, "getSize$d", jint, ()) for d in image_order]
    size_dict = Dict(zip(image_order, sizes))

    for c in image_order
        if !in(c, order)
            @assert (size_dict[c] == 1) "Non-singleton dimension \"$c\" is not present in the requested image order \"$order\""
            delete!(sizes_dict, c)
        end
    end

    arr = openbytes(oxr, 0)

    for i in 1:(prod(size_dict[d] for d in "TZC")-1)
        arr_nd = openbytes(oxr, i)
        append!(arr,arr_nd)
    end

    if islittleendian == 0
        @. arr = ntoh(arr)
    end
    arr = reinterpret(getpixeltype(oxr), arr)

    im = reshape(arr, (sizes...,))
    im = permutedims(im, [findfirst(c, image_order) for c in order])

    return im
end

function bf_import(fname::String; order="TZYXC")
    oxr = OMEXMLReader()
    set_id(oxr, fname)
    xml = parse_string(jcall(oxr.meta, "dumpXML", JString, ()))
    images = Array{ImageMeta,1}()

    metalst = get_elements_by_tagname(root(xml), "Image")
    for i = 1:length(metalst)
        set_series(oxr, i-1)
        img = open_stack(oxr; order = "TZYXC")
        properties = xml_to_dict(metalst[i])
        push!(images, ImageMeta(img, properties))
    end

    return images
end

function metadata(fname::String)
    oxr = OMEXMLReader()
    set_id(oxr, fname)
    xml = parse_string(jcall(oxr.meta, "dumpXML", JString, ()))
    properties = Dict{String, Any}()
    metalst = get_elements_by_tagname(root(xml), "Image")

    SizeC = jcall(oxr.reader, "getSizeC", jint, ())

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
