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

function open_stack(fname::String; stdout_redirect=STDOUT)

    rd, wr = redirect_stdout()
    oxr = OMEXMLReader()
    set_id(oxr, fname)

    SizeX = jcall(oxr.reader, "getSizeX", jint, ())
    SizeY = jcall(oxr.reader, "getSizeY", jint, ())
    SizeC = jcall(oxr.reader, "getSizeC", jint, ())
    SizeZ = jcall(oxr.reader, "getSizeZ", jint, ())
    SizeT = jcall(oxr.reader, "getSizeT", jint, ())
    order = jcall(oxr.reader, "getDimensionOrder", JString, ())

    arr = openbytes(oxr, 0)

    for i in 1:((SizeC*SizeZ*SizeT)-1)
        arr_nd = openbytes(oxr, i)
        append!(arr,arr_nd)
    end

        if islittleendian == 0
                @. arr = ntoh(arr)
        end
    arr = reinterpret(getpixeltype(oxr), arr)

    #Scikit image order of dimension TZXYC (permutedims)
    if order == "XYCZT"
        im = reshape(arr, (SizeX, SizeY, SizeC, SizeZ, SizeT))
        im = permutedims(im, [5,4,1,2,3])
    elseif order == "XYZTC"
        im = reshape(arr, (SizeX, SizeY, SizeZ, SizeT, SizeC))
        im = permutedims(im, [4,3,1,2,5])
    end


    redirect_stdout(STDOUT)
    @async begin
            while !eof(rd)
                    write(stdout_redirect, read(rd))
            end
            close(rd)
    end
    return im

end

function bf_import(fname::String; stdout_redirect=STDOUT)
        out = STDOUT
        rd, wr = redirect_stdout()

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

    redirect_stdout(out)
    @async begin
            while !eof(rd)
                    write(stdout_redirect, read(rd))
            end
            close(rd)
    end
    return images
end

function metadata(fname::String; stdout_redirect=STDOUT)

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

	redirect_stdout(STDOUT)
	@async begin
		while !eof(rd)
			write(stdout_redirect, read(rd))
		end
		close(rd)
	end
	return properties, metalst, xml
end

function starting(MEM::Int)

	# download bioformats_package.jar at https://www.openmicroscopy.org/bio-formats/downloads/

	bfpkg_path = "./jars/bioformats_package.jar"
	try
		JavaCall.init(["-ea", "-Xmx$(MEM)M", "-Djava.class.path=$bfpkg_path"])
	catch
	end

end

end
