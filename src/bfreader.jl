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
