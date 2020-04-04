# LogRoller.jl

[![Build Status](https://travis-ci.org/tanmaykm/LogRoller.jl.png)](https://travis-ci.org/tanmaykm/LogRoller.jl) 
[![Build Status](https://ci.appveyor.com/api/projects/status/github/tanmaykm/LogRoller.jl?branch=master&svg=true)](https://ci.appveyor.com/project/tanmaykm/logroller-jl/branch/master) 
[![Coverage Status](https://coveralls.io/repos/github/tanmaykm/LogRoller.jl/badge.svg?branch=master)](https://coveralls.io/github/tanmaykm/LogRoller.jl?branch=master)

Provides:
- `RollingFileWriter` - `IO` implementation to a file writer that rotates files based on file size.
- `RollingLogger` - `AbstractLogger` implementation that uses a `RollingFileWriter` for output.
- `postrotate` - Registers a callback function to be invoked with the rotated file name just after the current log file is rotated. The file name of the rotated file is passed as an argument. The function is blocking and so any lengthy operation that needs to be done should be done asynchronously.


## `RollingFileWriter`

A file writer that implements the `IO` interface, but only provides `write` methods. It also implements a transparent wrapper which allows it to be used to stream `stdin` and `stdout` of spawned processes into it.

Constructor parameters:
- `filename`: name (including path) of file to log into
- `sizelimit`: size of file (in bytes) after which the file should be rotated
- `nfiles`: number of rotated files to maintain

Rotates files as below:

- `<filename>` : active file
- `<filename>_1.gz` : last rotated file
- `<filename>_2.gz` : previous <filename>_1.gz rotated to <filename>_2.gz
- `<filename>_3.gz` : previous <filename>_2.gz rotated to <filename>_3.gz
- ...
- `<filename>_n.gz` : last rotated file is discarded when rotated


## `RollingFileWriterTee`

Tees raw log entries made a RollingFileWriter on to a Julia `AbstractLogger`.

Each line of text is taken as a single log message.

All log entries are made with the same log level, which can be provided during construction. It leaves
further examination/parsing of log messages (to extract parameters, or detect exact log levels) to the
downstream logger.

Constructor parameters in addition to those for `RollingFileWriter`:
- `logger`: instance of AbstractLogger to tee log entries to
- `assumed_level`: level of the log messages to assume (default Info)


## `RollingLogger`

A logger that implements `AbstractLogger` interface and uses a `RollingFileWriter` to provide log rotation.

Construction parameters:
- `filename`: name (including path) of file to log into
- `sizelimit`: size of file (in bytes) after which the file should be rotated
- `nfiles`: number of rotated files to maintain
- `level`: log level (default: `Logging.Info`)

## Examples

Using `RollingFileWriter`

```julia
julia> using LogRoller

julia> io = RollingFileWriter("/tmp/mylog.log", 1000, 3);

julia> println(io, "hello roller")

julia> write(io, b"hello world\n")

shell> cat /tmp/mylog.log
hello roller
hello world
```

Using `RollingFileWriter` with `stdout` and `stderr` streams

```julia
julia> using LogRoller

julia> io = RollingFileWriter("/tmp/mylog.log", 1000, 3);

julia> run(pipeline(`myshellscript.sh`; stdout=io, stderr=io));
```

Using `RollingFileWriterTee`

```julia
julia> using LogRoller, Logging

julia> io = RollingFileWriterTee("/tmp/mylog.log", 1000, 3, ConsoleLogger(stderr));

julia> run(pipeline(`myshellscript.sh`; stdout=io, stderr=io));
```

Using `RollingLogger`

```julia
julia> using Logging, LogRoller

julia> logger = RollingLogger("/tmp/mylog.log", 1000, 3, Logging.Debug);

julia> postrotate(logger) do rotatedfile
           # e.g. code to upload file to permanent store
           # ...
       end

julia> with_logger(logger) do
       @info("Hello RollingLogger")
       end

shell> cat /tmp/mylog.log
hello roller
hello world
┌ Info: 2019-12-03T09:26:33.694: Hello RollingLogger
└ @ Main REPL[11]:2
```

RollingLogger automatically adds the current timestamp to the log line. A timestamp can also be optionally provided in the log message keywords. By default, RollingLogger considers a keyword arg with a name `time` to indicate the timestamp of the log message. It uses the value specified in that as the timestamp if it is found to be either a `DateTime` or `Float64` (UNIX time). If a timestamp is detected in the keywords, it is used as the timestamp for the message and removed from the keywords.

```julia
julia> using Logging, LogRoller, Dates

julia> logger = RollingLogger("/tmp/mylog.log", 1000, 3, Logging.Debug);

julia> with_logger(logger) do
       @info("log with timestamp", time=DateTime(2010, 1, 1, 1, 1, 1))
       end

shell> cat /tmp/mylog.log
┌ Info: 2010-01-01T01:01:01: log with timestamp
└ @ Main REPL[8]:2
```

The name of keyword argument to use as timestamp can be set while initializing a RollingLogger.

```julia
julia> using Logging, LogRoller, Dates

julia> logger = RollingLogger("/tmp/mylog.log", 1000, 3, Logging.Debug, timestamp_identifier=:clock);

julia> with_logger(logger) do
       @info("log with timestamp", clock=DateTime(2010, 1, 1, 1, 1, 1))
       end

shell> cat /tmp/mylog.log
┌ Info: 2010-01-01T01:01:01: log with timestamp
└ @ Main REPL[3]:2
```

