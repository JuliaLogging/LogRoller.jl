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

