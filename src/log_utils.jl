"""
Custom JSON serialization of log entries.

Values that have no natural JSON form are written as their printed form, or
as an array in the case of `Core.SimpleVector`. Non-finite floats are written
as `null`, which is also what the default JSON writer did before JSON.jl 1.0.

JSON.jl 1.x customises writing through a `JSONStyle` and `lower` methods,
pre-1.0 through a `Serialization` and `show_json` methods; `LogEntrySerialization`
is one or the other depending on the JSON version loaded, and `write_json`
is the single entry point the rest of the package uses.
"""
struct LogEntrySerialization <: (JSON_V1 ? JSON.JSONStyle : CommonSerialization) end

const LoweredTypes = Union{Function, Module, Ptr, Core.SimpleVector, DataType, Logging.LogLevel, Tuple{Exception,Any}}

_lower(m::Function) = string(m)
_lower(m::Module) = string(m)
_lower(ptr::Ptr) = string(ptr)
_lower(sv::Core.SimpleVector) = [sv...]
_lower(typ::DataType) = string(typ)
_lower(level::Logging.LogLevel) =
    (level == Logging.Debug) ? "Debug" :
    (level == Logging.Info)  ? "Info" :
    (level == Logging.Warn)  ? "Warn" :
    (level == Logging.Error) ? "Error" :
    "LogLevel($(level.level))"
function _lower(exception::Tuple{Exception,Any})
    iob = IOBuffer()
    Base.show_exception_stack(iob, [exception])
    String(take!(iob))
end

@static if JSON_V1
    JSON.lower(::LogEntrySerialization, x::LoweredTypes) = _lower(x)
    # pre-1.0 JSON wrote NaN and Inf as null; 1.x refuses them unless told otherwise
    JSON.lower(::LogEntrySerialization, x::AbstractFloat) = isfinite(x) ? x : nothing
    write_json(io::IO, x) = JSON.json(io, x; style=LogEntrySerialization())
else
    show_json(io::StructuralContext, ser::LogEntrySerialization, x::LoweredTypes) = show_json(io, ser, _lower(x))
    write_json(io::IO, x) = JSON.show_json(io, LogEntrySerialization(), x)
end

as_text(str::String) = str
function as_text(obj)
    iob = IOBuffer()
    lim = LimitIO(iob, 4*1024)  # fixing it as of now to a large enough size for most use cases
    try
        show(lim, "text/plain", obj)
    catch ex
        if isa(ex, LimitIOException)
            # ignore and take what was printed
            print(iob, "...")
        else
            rethrow()
        end
    end

    String(take!(iob))
end

"""
IndexedLogEntry represents a log entry as a dictionary and its
indexable attributes in a form that is useful to a logging sink.

The index part contains metadata that are to be indexed. Event metadata
consists of attributes like level, module, filepath, line, job id,
process id, user id, etc. It also includes application specific
keywords that the originating piece of code wishes to index.

Keywords that should be considered as metadata are indicated via the
`indexable` constructor parameter.

What metadata can be indexed depends on the type of sink and whether
it has support to index certain types of attributes. Attributes that
the sink can not index are made part of the message itself for storage.

The message part can contain the following keys unless they are empty:
- `metadata`: event metadata that could not be indexed
- `message`: the log message string
- `keywords`: any keywords provided

Constructor parameters:
- `log`: Named tuple containing args to the handle_message method, e.g.: (level, message, _module, group, id, file, line, kwargs)
- `indexable`: list of names from `log` and `log.kwargs` that should be included in the index
"""
struct IndexedLogEntry
    index::Dict{Symbol,Any}
    message::Dict{Symbol,Any}
end

function IndexedLogEntry(log, indexable::Vector{Symbol}=[:level, :module, :filepath, :line])
    index = Dict{Symbol, Any}()
    metadata = Dict{Symbol,Any}()
    keywords = Dict(log.kwargs)

    log_prop_names = propertynames(log)
    for name in log_prop_names
        (name === :kwargs) && continue # skip the kwargs, deal with that separately
        (name === :message) && continue # skip message, we are dealing with that separately
        ((name in indexable) ? index : metadata)[name] = getproperty(log, name)
    end
    for name in keys(keywords)
        (name in log_prop_names) && continue # avoid clobbering reserved names
        if name in indexable
            index[name] = keywords[name]
            delete!(keywords, name)
        end
    end

    message = Dict{Symbol,Any}()
    messagestr = as_text(log.message)
    isempty(messagestr)     || (message[:message]  = messagestr)
    isempty(metadata)       || (message[:metadata] = metadata)
    isempty(keywords)       || (message[:keywords] = keywords)

    IndexedLogEntry(index, message)
end

message_string(entry::IndexedLogEntry, size_limit::Int, newline::Bool=false) = message_string(entry.message, size_limit, newline)
function message_string(message::Dict{Symbol,Any}, size_limit::Int, newline::Bool=false)
    iob = IOBuffer()
    lim = LimitIO(iob, size_limit)
    try
        write_json(lim, message)
        newline && write(lim, '\n')
    catch ex
        if isa(ex, LimitIOException)
            if haskey(message, :keywords)
                # strip off keywords (if any) and retry
                delete!(message, :keywords)
                return message_string(message, size_limit, newline)
            elseif haskey(message, :message)
                # strip off the message and retry (we retain only the metadata in the worst case)
                delete!(message, :message)
                return message_string(message, size_limit, newline)
            end
        end
        rethrow(ex)
    end
    String(take!(iob))
end
