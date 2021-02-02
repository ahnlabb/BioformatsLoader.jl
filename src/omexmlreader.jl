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

function OMEXMLReader(f::Function, filename::String)
    oxr = OMEXMLReader(filename)
    try
        f(oxr)
    finally
        close(oxr)
    end
end

Base.close(oxr::OMEXMLReader) = jcall(oxr.reader, "close", Nothing, ())

function OMEXMLReader(filename::String)
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
        jcall(oxr.reader, "openBytes", Vector{jbyte}, (jint,), index)
    end
end

function set_series!(oxr::OMEXMLReader, index::Int)
    jcall(oxr.reader, "setSeries", Nothing, (jint,), index)
end

function getpixeltype(oxr::OMEXMLReader)
    id = jcall(oxr.reader, "getPixelType", jint, ())
    return datatypes[id+1]
end

function islittleendian(oxr::OMEXMLReader)
    jcall(oxr.reader, "isLittleEndian", jboolean, ())
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
