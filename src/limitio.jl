# limits number of bytes written to an io stream (originally from https://github.com/JuliaDebug/Debugger.jl/blob/master/src/limitio.jl)
# useful to detect messages that would go over limit when converted to JSON.
mutable struct LimitIO{IO_t <: IO} <: IO
    io::IO_t
    maxbytes::Int
    n::Int # max bytes to write
end
LimitIO(io::IO, maxbytes) = LimitIO(io, maxbytes, 0) 

struct LimitIOException <: Exception end

function Base.write(io::LimitIO, v::UInt8)
    io.n > io.maxbytes && throw(LimitIOException())
    io.n += write(io.io, v)
end
