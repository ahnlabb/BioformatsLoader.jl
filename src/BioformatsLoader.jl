module BioformatsLoader
using JavaCall
using LightXML
using ImageMetadata

using ImageAxes, SimpleTraits
@traitimpl TimeAxis{Axis{:t}}

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
    starting

const JServiceFactory = @jimport loci.common.services.ServiceFactory
const JService = @jimport loci.common.services.Service
const JIFormatReader = @jimport loci.formats.IFormatReader
const JImageReader = @jimport loci.formats.ImageReader
const JOMEXMLMetadata = @jimport loci.formats.ome.OMEXMLMetadata
const JMetadataStore = @jimport loci.formats.meta.MetadataStore

const JLength = @jimport ome.units.quantity.Length
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

# this seems broken...
# function openbytes(oxr::OMEXMLReader, index::Int, data::Vector{jbyte})
#     jcall(oxr.reader, "openBytes", Vector{jbyte}, (jint, Vector{jbyte}), index, data)
# end

function set_series(oxr::OMEXMLReader, index::Int)
    jcall(oxr.reader, "setSeries", Nothing, (jint,), index)
end

function getpixeltype(oxr::OMEXMLReader)
    id = jcall(oxr.reader, "getPixelType", jint, ())
    return datatypes[id+1]
end

function getImageCount(oxr::OMEXMLReader)
    return jcall(oxr.reader, "getImageCount", jint, ())
end

function islittleendian(oxr::OMEXMLReader)
    Bool(jcall(oxr.reader, "isLittleEndian", jboolean, ()))
end

"""
    open_img()
"""
function open_img(oxr::OMEXMLReader, index::Int)
    sx = jcall(oxr.reader, "getSizeX", jint, ())
    sy = jcall(oxr.reader, "getSizeY", jint, ())
    arr = reinterpret(getpixeltype(oxr), openbytes(oxr, index))
    if islittleendian(oxr) == 0
            @. arr = ntoh(arr)
    end
    return reshape(arr, (sx, sy))
end

function read_stack(oxr::OMEXMLReader)
    Size = (
        x = jcall(oxr.reader, "getSizeX", jint, ()),
        y = jcall(oxr.reader, "getSizeY", jint, ()),
        c = jcall(oxr.reader, "getSizeC", jint, ()),
        z = jcall(oxr.reader, "getSizeZ", jint, ()),
        t = jcall(oxr.reader, "getSizeT", jint, ())
    )

    PT = getpixeltype(oxr)

    order = jcall(oxr.reader, "getDimensionOrder", JString, ())
    axisnames = ((Symbol(lowercase(c)) for c in order)...,)
    size = ntuple(5) do i
        getfield(Size, axisnames[i])
    end

    buf_size = Size.x * Size.y * sizeof(PT)
    nslices = Int(Size.c) * Size.z * Size.t

    @assert getImageCount(oxr) == nslices 

    arr = Array{jbyte}(undef, buf_size, nslices)
    for i in 0:(nslices-1)
        buf = openbytes(oxr, i)
        copyto!(view(arr, :, i+1), buf)
    end

    if islittleendian(oxr)
        @. arr = ntoh(arr)
    end
    # Avoid `ReinterpretArray` and `ReshapeArray` wrappers
    arr = collect(reinterpret(PT, arr))

    return AxisArray(reshape(arr, size), axisnames...)
end

"""
    open_stack(fname)

Open the first stack in `fname` in TZXYC order.
"""
function open_stack(fname::String; stdout_redirect=stdout)

    rd, wr = redirect_stdout()
    oxr = OMEXMLReader()
    set_id(oxr, fname)

    order = jcall(oxr.reader, "getDimensionOrder", JString, ())

    im = read_stack(oxr)
    #Scikit image order of dimension TZXYC (permutedims)
    im = permutedims(im, (:t, :z, :x, :y, :c))

    redirect_stdout(stdout)
    @async begin
            while !eof(rd)
                    write(stdout_redirect, read(rd))
            end
            close(rd)
    end
    return im

end

function bf_import(fname::String; stdout_redirect=stdout)
        out = stdout
        rd, wr = redirect_stdout()

    oxr = OMEXMLReader()
    set_id(oxr, fname)
    xml = parse_string(jcall(oxr.meta, "dumpXML", JString, ()))
    images = Array{ImageMeta,1}()

    metalst = get_elements_by_tagname(root(xml), "Image")
    for i = 1:length(metalst)
        set_series(oxr, i-1)
        img = read_stack(oxr)
        properties = Dict{String, Any}()
        for a = attributes(metalst[i])
            push!(properties, "Image$(name(a))"=>value(a))
        end
        for a = attributes(find_element(metalst[i], "Pixels"))
            push!(properties, "Pixel$(name(a))"=>value(a))
        end

        push!(images, ImageMeta(img, properties))
    end

    redirect_stdout(out)
    @async begin
            while !eof(rd)
                    write(stdout_redirect, read(rd))
            end
            close(rd)
    end
    return images
end

function metadata(fname::String; stdout_redirect=stdout)

    rd, wr = redirect_stdout()

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

    redirect_stdout(stdout)
    @async begin
        while !eof(rd)
            write(stdout_redirect, read(rd))
        end
        close(rd)
    end
    return properties, metalst, xml
end

function init(;memory=1024::Int)
    bfpkg_path = joinpath(@__DIR__, "..", "deps", "bioformats_package.jar")
    sb6_path   = joinpath(@__DIR__, "..", "deps", "SlideBook6Reader.jar")
    JavaCall.init(["-ea", "-Xmx$(memory)M", "-Djava.class.path=$bfpkg_path:$sb6_path"])
end

end
