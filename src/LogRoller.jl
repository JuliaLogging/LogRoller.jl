module LogRoller

using Dates
using Logging
using CodecZlib
using JSON
using JSON.Serializations: CommonSerialization, StandardSerialization
using JSON.Writer: StructuralContext
import JSON: show_json

import Logging: shouldlog, min_enabled_level, catch_exceptions, handle_message
import Base: write, close, rawhandle
export RollingLogger, RollingFileWriter, postrotate

const BUFFSIZE = 1024*16  # try and read 16K pages when possible
const DEFAULT_MAX_LOG_ENTRY_SIZE = 256*1024

const showvalue = VERSION ≥ v"1.11.0-DEV.1786" ? Base.CoreLogging.showvalue : Logging.showvalue

include("limitio.jl")
include("log_utils.jl")

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
    postrotate::Union{Nothing,Function}

    function RollingFileWriter(filename::String, sizelimit::Int, nfiles::Int; rotate_on_init=false)
        stream = open(filename, "a")
        filesize = stat(stream).size
        io = new(filename, sizelimit, nfiles, filesize, stream, ReentrantLock(), nothing)
        if rotate_on_init && filesize > 0
            rotate_file(io)
        end
        return io
    end
end

"""
Register a function to be called with the rotated file name just after the current log file is rotated.
The file name of the rotated file is passed as an argument. The function is blocking and so any lengthy
operation that needs to be done should be done asynchronously.
"""
function postrotate(fn::Function, io::RollingFileWriter)
    io.postrotate = fn
    nothing
end

"""
Close any open file handle and streams.
A closed object must not be used again.
"""
function close(io::RollingFileWriter)
    close(io.stream)
end

"""
Write into the underlying stream, rolling over as and when necessary.
"""
write(io::RollingFileWriter, byte::UInt8) = _write(io, byte)
write(io::RollingFileWriter, str::Union{SubString{String}, String}) = _write(io, str)
write(io::RollingFileWriter, buff::Vector{UInt8}) = _write(io, buff)

function _write(io::RollingFileWriter, args...)
    bytes_written = 0
    lock(io.lck) do
        bytes_written += write(io.stream, args...)
        io.filesize += bytes_written
        flush(io.stream)
        if io.filesize >= io.sizelimit
            with_logger(NullLogger()) do
                rotate_file(io)
            end
        end
    end
    return bytes_written
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

    # call postrotate hook if one is registered
    (io.postrotate === nothing) || io.postrotate(nthlogfile)

    nothing
end

"""
RollingLogger(filename, sizelimit, nfiles, min_level=Info; timestamp_identifier::Symbol=:time, format::Symbol=:console)
Log into a log file. Rotate log file based on file size. Compress rotated logs.

Logs can be formatted as JSON by setting the optional keyword argument `format` to `:json`. A JSON formatted log entry
is a JSON object. It should have these keys (unless they are empty):
The message part can contain the following keys unless they are empty:
- `metadata`: event metadata e.g. timestamp, line, filename, ...
- `message`: the log message string
- `keywords`: any keywords provided
"""
mutable struct RollingLogger <: AbstractLogger
    stream::RollingFileWriter
    min_level::LogLevel
    message_limits::Dict{Any,Int}
    timestamp_identifier::Symbol
    format::Symbol
    entry_size_limit::Int
end
function RollingLogger(filename::String, sizelimit::Int, nfiles::Int, level=Logging.Info; timestamp_identifier::Symbol=:time, format::Symbol=:console, entry_size_limit::Int=DEFAULT_MAX_LOG_ENTRY_SIZE, rotate_on_init=false)
    stream = RollingFileWriter(filename, sizelimit, nfiles, rotate_on_init=rotate_on_init)
    RollingLogger(stream, level, Dict{Any,Int}(), timestamp_identifier, format, entry_size_limit)
end

"""
Register a function to be called with the rotated file name just after the current log file is rotated.
The file name of the rotated file is passed as an argument. The function is blocking and so any lengthy
operation that needs to be done should be done asynchronously.
"""
postrotate(fn::Function, io::RollingLogger) = postrotate(fn, io.stream)

"""
Close any open file handle and streams.
A closed object must not be used again.
"""
close(logger::RollingLogger) = close(logger.stream)

shouldlog(logger::RollingLogger, level, _module, group, id) = get(logger.message_limits, id, 1) > 0

min_enabled_level(logger::RollingLogger) = logger.min_level

catch_exceptions(logger::RollingLogger) = false

function get_timestamp(logger::RollingLogger, kwargs)
    try
        for (key, val) in kwargs
            if key === logger.timestamp_identifier
                if isa(val, DateTime)
                    return (val, true)
                else
                    return (Dates.unix2datetime(Float64(val)), true)
                end
            end
        end
    catch
        # could not convert val to DateTime, fallback to now()
    end
    (now(), false)
end

function handle_message(logger::RollingLogger, level, message, _module, group, id, filepath, line; maxlog=nothing, kwargs...)
    if maxlog !== nothing && maxlog isa Integer
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return
    end

    if logger.format === :json
        timestamp, kwarg_timestamp = get_timestamp(logger, kwargs)
        log = (level=level, message=message, _module=_module, group=group, id=id, filepath=filepath, line=line, kwargs=kwargs)
        log = merge(log, [logger.timestamp_identifier=>timestamp])
        logentry = IndexedLogEntry(log, Symbol[])
        write(logger.stream, message_string(logentry, logger.entry_size_limit, true))
    else # if logger.format === :console
        buf = IOBuffer()
        lim = LimitIO(buf, logger.entry_size_limit)
        limited = false
        try
            iob = IOContext(lim, logger.stream)
            levelstr = level == Logging.Warn ? "Warning" : string(level)
            timestamp, kwarg_timestamp = get_timestamp(logger, kwargs)
            msglines = split(chomp(string(message)), '\n')
            println(iob, "┌ ", levelstr, ": ", timestamp, ": ", msglines[1])
            for i in 2:length(msglines)
                println(iob, "│ ", msglines[i])
            end
            for (key, val) in kwargs
                kwarg_timestamp && (key === logger.timestamp_identifier) && continue
                print(iob, "│   ", key, " = ")
                showvalue(iob, val)
                println(iob)
            end
            println(iob, "└ @ ", something(_module, "nothing"), " ", something(filepath, "nothing"), ":", something(line, "nothing"))
        catch ex
            isa(ex, LimitIOException) || rethrow(ex)
            limited = true
        end
        write(logger.stream, take!(buf))
        limited && write(logger.stream, UInt8[0x0a])
    end

    nothing
end

end # module
