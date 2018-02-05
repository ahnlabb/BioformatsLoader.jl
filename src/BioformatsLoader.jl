module BioformatsLoader
using JavaCall
using LightXML
using ImageMetadata

export
	create_service,
	set_id,
	OMEXMLReader,
	openbytes,
	set_series,
	getlength,
	getpixeltype,
	open_img,
	bf_import

const JServiceFactory = @jimport loci.common.services.ServiceFactory
const JOMEXMLService = @jimport loci.formats.services.OMEXMLService #unused
const JService = @jimport loci.common.services.Service
const JIFormatReader = @jimport loci.formats.IFormatReader
const JImageReader = @jimport loci.formats.ImageReader
const JOMEXMLMetadata = @jimport loci.formats.ome.OMEXMLMetadata
const JMetadataStore = @jimport loci.formats.meta.MetadataStore

const JLength = @jimport ome.units.quantity.Length

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

        jcall(reader, "setMetadataStore", Void, (JMetadataStore,), meta)
        OMEXMLReader(reader, meta)
end


function set_id(oxr::OMEXMLReader, fname::AbstractString)
        jcall(oxr.reader, "setId", Void, (JString,), string(fname))
end

function openbytes(oxr::OMEXMLReader, index::Int)
        jcall(oxr.reader, "openBytes", Vector{jbyte}, (jint,), index)
end

function set_series(oxr::OMEXMLReader, index::Int)
        jcall(oxr.reader, "setSeries", Void, (jint,), index)
end

function getlength(oxr::OMEXMLReader, name::String, imageindex::Int)
        jcall(oxr.meta, "get" * name, JLength, (jint,), imageindex)
end

function getpixeltype(oxr::OMEXMLReader)
        id = jcall(oxr.reader, "getPixelType", jint, ())
	return datatypes[id+1]
end

function islittleendian(oxr::OMEXMLReader)
        jcall(oxr.reader, "isLittleEndian", jboolean, ())
end

function open_img(oxr::OMEXMLReader, index::Int)
	@assert islittleendian(oxr) == 1
	sx = jcall(oxr.reader, "getSizeX", jint, ())
	sy = jcall(oxr.reader, "getSizeY", jint, ())
	println((sx, sy))
	arr = reinterpret(getpixeltype(oxr), openbytes(oxr, index))
	return reshape(arr, (sx, sy))
end

datatypes = [Int8,UInt8,Int16,UInt16,Int32,UInt32,Float32,Float64,Bool]

function bf_import(fname::String)
	oxr = OMEXMLReader()
	set_id(oxr, fname)
	xml = parse_string(jcall(oxr.meta, "dumpXML", JString, ()))
	images = Array{ImageMeta,1}()

	metalst = get_elements_by_tagname(root(xml), "Image")
	for i = 1:length(metalst)
		set_series(oxr, i-1)
		img = open_img(oxr, 0)
		properties = Dict{String, Any}()
		for a = attributes(metalst[i])
			push!(properties, "Image$(name(a))"=>value(a))
		end
		for a = attributes(find_element(metalst[i], "Pixels"))
			push!(properties, "Pixel$(name(a))"=>value(a))
		end

		push!(images, ImageMeta(img, properties))
	end
	return images
end

end
