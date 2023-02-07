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

    function OMEXMLReader()
        # Make sure JavaCall and logger have been initialized
        ensure_init()
        service = create_service("loci.formats.services.OMEXMLService")
        meta = jcall(service, "createOMEXMLMetadata", JOMEXMLMetadata, ())
        reader = convert(JIFormatReader, JImageReader(()))

        jcall(reader, "setMetadataStore", Nothing, (JMetadataStore,), meta)
        new(reader, meta)
    end
end


function OMEXMLReader(f::Function, filename::AbstractString)
    oxr = OMEXMLReader(filename)
    try
        f(oxr)
    finally
        close(oxr)
    end
end

Base.close(oxr::OMEXMLReader) = jcall(oxr.reader, "close", Nothing, ())

function OMEXMLReader(filename::AbstractString)
    oxr = OMEXMLReader()
    set_id!(oxr, filename)
    oxr
end

function local_frame(f::Function; capacity=16)
    JNI.PushLocalFrame(jint(capacity))
    try
        f()
    finally
        JNI.PopLocalFrame(C_NULL)
    end
end

function set_id!(oxr::OMEXMLReader, filename::AbstractString)
    jcall(oxr.reader, "setId", Nothing, (JString,), string(filename))
end

function openbytes(oxr::OMEXMLReader, index::Int)
    local_frame() do
        # openBytes(int no) : gets image plane number no
        jcall(oxr.reader, "openBytes", Vector{jbyte}, (jint,), index)
    end
end

# a version that yields only a region of interest
"""
    openbytes(oxr::OMEXMLReader, index::Int, x::Int, y::Int, w::Int, h::Int)

returns a byte[] of the current dataset in the reader oxr and frame index index starting at x-position `x` and y-position `y` (1-based indexing)
with a width `w` and height `h`. 
"""
function openbytes(oxr::OMEXMLReader, index::Int, x::Int, y::Int, w::Int, h::Int)
    local_frame() do
        # openBytes(int no, int x int y, int w, int h)
        jcall(oxr.reader, "openBytes", Vector{jbyte}, (jint, jint, jint, jint, jint), index, x-1, y-1, w, h)
    end
end

function get_xywh(fsubidx, raw_size)
	(x, w, r_x), (y, h, r_y) = map(fsubidx, raw_size) do idx, sz
		if iscolon(idx)
			(1, sz, :)
		else
			bot, top = extrema(idx)
			len = top - bot + 1
			# this should even work for ranges of individual indices
			bot, len, idx .- bot .+ 1
		end
	end
    return x, y, w, h, (r_x, r_y)
end

function set_series!(oxr::OMEXMLReader, index::Int)
    jcall(oxr.reader, "setSeries", Nothing, (jint,), index)
end

function getpixeltype(oxr::OMEXMLReader)
    id = jcall(oxr.reader, "getPixelType", jint, ())
    return datatypes[id+1]
end

function islittleendian(oxr::OMEXMLReader)
    Bool(jcall(oxr.reader, "isLittleEndian", jboolean, ()))
end

function isinterleaved(oxr::OMEXMLReader)
    Bool(jcall(oxr.reader, "isInterleaved", jboolean, ()))
end

function get_dimension_order(oxr)
    jcall(oxr.reader, "getDimensionOrder", JString, ())
end

function get_size(oxr, d)
    jcall(oxr.reader, "getSize$d", jint, ())
end

function get_image_count(oxr)
    jcall(oxr.reader, "getImageCount", jint, ())
end

function get_xml(oxr)
    parse_string(jcall(oxr.meta, "dumpXML", JString, ()))
end

function get_RGB_channel_count(oxr)
    jcall(oxr.reader, "getRGBChannelCount", jint, ())
end
