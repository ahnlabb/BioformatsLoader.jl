function xml_to_dict(node::XMLElement; path="")
    dict = Dict{String, Any}()
    for a=attributes(node)
        bt = base_type_parser("$(name(node)).$(name(a))")
        val = value(a)
        if !(bt isa Nothing)
            val = bt(val)
        end
        dict[name(a)] = val
    end
    for n=child_elements(node)
        nxt = xml_to_dict(n)
        if name(n) in keys(dict)
            cur = dict[name(n)]
            if cur isa Array
                push!(cur, nxt)
            else
                dict[name(n)] = [cur, nxt]
            end
        else
            dict[name(n)] = nxt
        end
    end
    return dict
end

xsd_types = Dict("xsd:byte"=>(x -> parse(Int8, x)),
                 "xsd:decimal"=>(x -> parse(Float64, x)),
                 "xsd:int"=>(x -> parse(Int32, x)),
                 "xsd:integer"=>(x -> parse(Int64, x)),
                 "xsd:long"=>(x -> parse(Int64, x)),
                 "xsd:short"=>(x -> parse(Int16, x)),
                 "xsd:unsignedLong"=>(x -> parse(UInt64, x)),
                 "xsd:unsignedInt"=>(x -> parse(UInt32, x)),
                 "xsd:unsignedShort"=>(x -> parse(UInt16, x)),
                 "xsd:unsignedByte"=>(x -> parse(UInt8, x)),
                 "xsd:dateTime"=>(x->DateTime(x, Date.DateFormat("yyyy-mm-ddTHH:MM:SS.sss"))),
                 "xsd:float"=>(x -> parse(Float64, x)),
                 "xsd:double"=>(x -> parse(Float64, x)),
                 "xsd:boolean"=>(x -> parse(Bool, x))
                )



function parse_schema(doc::Nothing)
end

function parse_schema(doc::XMLDocument)
    children = child_elements(root(doc))
    return Dict(attribute(e, "name")=>parse_schema(e) for e=children)
end

function parse_schema(element::XMLElement)
    if name(element) == "simpleType"
        r = find_element(element, "restriction")
        return attribute(r, "base")
    elseif name(element) == "complexType"
        return Dict(attribute(e, "name")=>parse_schema(e) for e=element["attribute"])
    elseif name(element) == "attribute"
        if has_attribute(element, "type")
            return attribute(element, "type")
        else
            return parse_schema(find_element(element, "simpleType"))
        end
    elseif name(element) == "element"
        try
            return parse_schema([element["simpleType"];element["complexType"]][1])
        catch
        end
    end
end

function base_type_parser(attribute)
    parts = split(attribute, ".")
    element = schema
    try
        for p=parts
            element = element[p]
        end
        while element in keys(schema)
            element = schema[element]
        end
        return xsd_types[element]
    catch KeyError
    end
end

schema_path = joinpath(@__DIR__, "..", "deps", "ome.xsd")
schema = parse_schema(LightXML.parse_file(schema_path))

