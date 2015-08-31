type Bias <: Layer; b; Bias(b::KUparam)=new(b); end

param(l::Bias)=l.b

Bias(d1, d...; o...)=Bias(KUparam(d1, d...; o...))
Bias(; o...)=Bias(KUparam(0; o...))

overwrites(l::Bias)=true
back_reads_x(l::Bias)=false
back_reads_y(l::Bias)=false

function forw(l::Bias, x; o...)
    (b,x)=initforw(l,x;o...)
    biasforw(b,x)
    return x
end

function initforw(l::Bias, x; predict=false, o...)
    nb = size(x, ndims(x)==1 ? 1 : ndims(x)-1)
    if isempty(l.b) 
        nz(l.b,:init,nothing) || (l.b.init = initzero)
        init(l.b, eltype(x), (nb,))
    end
    @assert length(l.b) == nb
    @assert eltype(l.b) == eltype(x)
    return ((predict && nz(l.b, :average, false)) ? (l.b.avg, x) : (l.b.arr, x))
end

function back(l::Bias, dy; incr=false, returndx=true, o...)
    initback(l, dy, incr)
    if incr
        biasback(l.b.inc, dy)
        axpy!(1, l.b.inc, l.b.diff)
    else
        biasback(l.b.diff, dy)
    end
    if returndx
        return dy
    end
end

function initback(l::Bias, dy, incr)
    nb = size(dy, ndims(dy)==1 ? 1 : ndims(dy)-1)
    @assert length(l.b) == nb
    @assert eltype(l.b) == eltype(dy)
    similar!(l.b, :diff, l.b.arr)
    incr && similar!(l.b, :inc, l.b.arr)
end

# We are implementing the CUDNN_ADD_SAME_C mode of cudnn:
# In this mode if x has dimensions (X1,X2,...,C,N) then
# bias has length=C.

biasforw(b::Vector, x::Vector)=(for i=1:length(x); x[i] = x[i] + b[i]; end)
biasback(db::Vector, dy::Vector)=(for i=1:length(dy); db[i]=dy[i]; end)

biasforw(b::Vector, x::Array)=(c=ndims(x)-1; for i=1:length(x); x[i] = x[i] + b[ind2sub(size(x),i)[c]]; end)
biasback(db::Vector, dy::Array)=(c=ndims(dy)-1; fill!(db, zero(eltype(db))); for i=1:length(dy); db[ind2sub(size(dy),i)[c]] += dy[i]; end)

biasforw(b, x::KUdense)=biasforw(b,x.arr)
biasback(db, dy::KUdense)=biasback(db, dy.arr)

GPU && (biasforw(b::CudaArray, x::CudaArray)=cudnnAddTensor(b, x; mode=CUDNN_ADD_SAME_C))
GPU && (biasback(db::CudaArray, dy::CudaArray)=cudnnConvolutionBackwardBias(dy, db))
