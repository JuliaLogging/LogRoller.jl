module LogRoller

using Dates
using Logging
using CodecZlib
using Logging

import Logging: shouldlog, min_enabled_level, catch_exceptions, handle_message
import Base: write, close
export RollingLogger, RollingFileWriter

const BUFFSIZE = 1024*16  # try and read 16K pages when possible

"""
A file writer that implements the `IO` interface, but only provides `write` methods.

Constructor parameters:
- filename: name (including path) of file to log into
- sizelimit: size of file (in bytes) after which the file should be rotated
- nfiles: number of rotated files to maintain
"""
mutable struct RollingFileWriter <: IO
    filename::String
    sizelimit::Int
    nfiles::Int
    filesize::Int
    stream::IO
    lck::ReentrantLock

    function RollingFileWriter(filename::String, sizelimit::Int, nfiles::Int)
        stream = open(filename, "a")
        filesize = stat(stream).size
        new(filename, sizelimit, nfiles, filesize, stream, ReentrantLock())
    end
end

close(io::RollingFileWriter) = close(io.stream)

write(io::RollingFileWriter, byte::UInt8) = _write(io, byte)
write(io::RollingFileWriter, str::Union{SubString{String}, String}) = _write(io, str)
write(io::RollingFileWriter, buff::Vector{UInt8}) = _write(io, buff)

function _write(io::RollingFileWriter, args...)
    lock(io.lck) do
        io.filesize += write(io.stream, args...)
        flush(io.stream)
        if io.filesize >= io.sizelimit
            with_logger(NullLogger()) do
                rotate_file(io)
            end
        end
    end
end

"""
Rotate files as below with increasing age:
    - <filename> : active file
    - <filename>_1.gz : last rotated file
    - <filename>_2.gz : previous <filename>_1.gz rotated to <filename>_2.gz
    - <filename>_3.gz : previous <filename>_2.gz rotated to <filename>_3.gz
    - ...
    - <filename>_n.gz : last rotated file is discarded when rotated
"""
function rotate_file(io::RollingFileWriter)
    for N in io.nfiles:-1:1
        nthlogfile = string(io.filename, "_", N, ".gz")
        if isfile(nthlogfile)
            if N == io.nfiles
                rm(nthlogfile) # discard
            else
                nextlogfile = string(io.filename, "_", N+1, ".gz")
                mv(nthlogfile, nextlogfile) # rotate
            end
        end
    end
    close(io.stream)
    nthlogfile = string(io.filename, "_", 1, ".gz")
    open(nthlogfile, "w") do fw
        cfw = GzipCompressorStream(fw)
        try
            open(io.filename, "r") do fr
                buff = Vector{UInt8}(undef, BUFFSIZE)
                while !eof(fr)
                    nbytes = readbytes!(fr, buff)
                    (nbytes > 0) && write(cfw, (nbytes < BUFFSIZE) ? view(buff, 1:nbytes) : buff)
                end
            end
        finally
            flush(cfw)
            close(cfw)
        end
    end
    io.stream = open(io.filename, "w")
    io.filesize = 0
    nothing
end

"""
RollingLogger(filename, sizelimit, nfiles, min_level=Info)
Log into a log file. Rotate log file based on file size. Compress rotated logs.
"""
mutable struct RollingLogger <: AbstractLogger
    stream::RollingFileWriter
    min_level::LogLevel
    message_limits::Dict{Any,Int}
end
function RollingLogger(filename::String, sizelimit::Int, nfiles::Int, level=Logging.Info)
    stream = RollingFileWriter(filename, sizelimit, nfiles)
    RollingLogger(stream, level, Dict{Any,Int}())
end

close(logger::RollingLogger) = close(logger.stream)

shouldlog(logger::RollingLogger, level, _module, group, id) = get(logger.message_limits, id, 1) > 0

min_enabled_level(logger::RollingLogger) = logger.min_level

catch_exceptions(logger::RollingLogger) = false

function handle_message(logger::RollingLogger, level, message, _module, group, id, filepath, line; maxlog=nothing, kwargs...)
    if maxlog !== nothing && maxlog isa Integer
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return
    end
    buf = IOBuffer()
    iob = IOContext(buf, logger.stream)
    levelstr = level == Logging.Warn ? "Warning" : string(level)
    timestr = DateTime(now())
    msglines = split(chomp(string(message)), '\n')
    println(iob, "┌ ", levelstr, ": ", timestr, ": ", msglines[1])
    for i in 2:length(msglines)
        println(iob, "│ ", msglines[i])
    end
    for (key, val) in kwargs
        println(iob, "│   ", key, " = ", val)
    end
    println(iob, "└ @ ", something(_module, "nothing"), " ", something(filepath, "nothing"), ":", something(line, "nothing"))
    write(logger.stream, take!(buf))
    nothing
end

end # module
