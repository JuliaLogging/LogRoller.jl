using LogRoller, Test, Logging, Dates, JSON

rolledfile(path, n) = string(path, "_", n, ".gz")

function test_filewriter()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)
        @test !isfile(filepath)
        @test !isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))

        # initialize
        io = RollingFileWriter(filepath, 1000, 3)
        @test isfile(filepath)
        logstr = "-"^100

        # not rolled yet
        println(io, logstr)
        @test !isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))

        # roll once
        for count in 1:10
            println(io, logstr)
        end
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))
        @test stat(filepath).size > 0
        @test stat(filepath).size < 1000
        @test stat(rolledfile(filepath, 1)).size > 0
        @test stat(rolledfile(filepath, 1)).size < 1000  # compressed

        # roll twice
        for count in 1:10
            println(io, logstr)
        end
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))
        @test isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))
        @test stat(filepath).size > 0
        @test stat(filepath).size < 1000
        @test stat(rolledfile(filepath, 1)).size > 0
        @test stat(rolledfile(filepath, 1)).size < 1000  # compressed
        @test stat(rolledfile(filepath, 2)).size > 0
        @test stat(rolledfile(filepath, 2)).size < 1000  # compressed

        # roll 4 times
        for count in 1:20
            println(io, logstr)
        end
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))
        @test isfile(rolledfile(filepath, 2))
        @test isfile(rolledfile(filepath, 3))
        @test !isfile(rolledfile(filepath, 4)) # max 3 rolled files
        @test stat(filepath).size > 0
        @test stat(filepath).size < 1000
        @test stat(rolledfile(filepath, 1)).size > 0
        @test stat(rolledfile(filepath, 1)).size < 1000  # compressed
        @test stat(rolledfile(filepath, 2)).size > 0
        @test stat(rolledfile(filepath, 2)).size < 1000  # compressed
        @test stat(rolledfile(filepath, 3)).size > 0
        @test stat(rolledfile(filepath, 3)).size < 1000  # compressed

        close(io)
        @test !isopen(io.stream)
    end
end

function test_logger()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)
        @test !isfile(filepath)
        @test !isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))

        # initialize
        logger = RollingLogger(filepath, 1000, 3)
        @test isfile(filepath)
        logstr = "-"^40 # account for headers added by logger

        # not rolled yet
        with_logger(logger) do
            @info(logstr)
        end
        @test !isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))

        # roll once
        with_logger(logger) do
            for count in 1:10
                @info(logstr)
            end
        end
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))
        @test stat(filepath).size > 0
        @test stat(filepath).size < 1000
        @test stat(rolledfile(filepath, 1)).size > 0
        @test stat(rolledfile(filepath, 1)).size < 1000  # compressed

        # roll 4 times
        with_logger(logger) do
            for count in 1:40
                @info(logstr)
            end
        end
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))
        @test isfile(rolledfile(filepath, 2))
        @test isfile(rolledfile(filepath, 3))
        @test !isfile(rolledfile(filepath, 4)) # max 3 rolled files
        @test stat(filepath).size > 0
        @test stat(filepath).size < 1000
        @test stat(rolledfile(filepath, 1)).size > 0
        @test stat(rolledfile(filepath, 1)).size < 1000  # compressed
        @test stat(rolledfile(filepath, 2)).size > 0
        @test stat(rolledfile(filepath, 2)).size < 1000  # compressed
        @test stat(rolledfile(filepath, 3)).size > 0
        @test stat(rolledfile(filepath, 3)).size < 1000  # compressed

        rm(rolledfile(filepath, 1))
        logger_roi = RollingLogger(filepath, 1000, 3, rotate_on_init=true)
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))

        close(logger)
        @test !isopen(logger.stream.stream)
    end
end

function test_process_streams()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)
        @test !isfile(filepath)
        @test !isfile(rolledfile(filepath, 1))

        io = RollingFileWriter(filepath, 1000, 3)
        @test isfile(filepath)

        julia = joinpath(Sys.BINDIR, "julia")
        cmd = pipeline(`$julia -e 'println("-"^100)'`; stdout=io, stderr=io)
        run(cmd)

        @test !isfile(rolledfile(filepath, 1))

        for count in 1:10
            run(cmd)
        end
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))

        close(io)
    end
end

function test_postrotate()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)
        @test !isfile(filepath)
        @test !isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))

        # initialize
        logger = RollingLogger(filepath, 1000, 3)
        rotatedfiles = Vector{String}()
        postrotate(logger) do rotatedfilename
            push!(rotatedfiles, rotatedfilename)
        end
        @test isfile(filepath)
        logstr = "-"^40 # account for headers added by logger

        # not rolled yet
        with_logger(logger) do
            @info(logstr)
        end
        @test !isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))

        # roll once
        with_logger(logger) do
            for count in 1:10
                @info(logstr)
            end
        end
        @test isfile(filepath)
        @test isfile(rolledfile(filepath, 1))
        @test !isfile(rolledfile(filepath, 2))
        @test !isfile(rolledfile(filepath, 3))
        @test stat(filepath).size > 0
        @test stat(filepath).size < 1000
        @test stat(rolledfile(filepath, 1)).size > 0
        @test stat(rolledfile(filepath, 1)).size < 1000  # compressed

        @test length(rotatedfiles) == 1
        @test rotatedfiles[1] == rolledfile(filepath, 1)
    end
end

function test_timestamp_handling()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)

        logger = RollingLogger(filepath, 1000, 3)
        testdt = DateTime(2000, 1, 1, 1, 1, 1, 1)
        timenow = time()
        dt_from_time = Dates.unix2datetime(timenow)
        with_logger(logger) do
            @info("without_timestamp")
            @info("without_timestamp", testarg=1)
            @info("with_timestamp", time=timenow)
            @info("with_timestamp", time=testdt)
            @info("with_timestamp", time=testdt, testarg=1)
            @test isfile(filepath)
        end
        close(logger)

        filecontents = readlines(filepath)
        @test length(filecontents) == 12
        dates = DateTime[]
        for line in filecontents
            if startswith(line, "┌ Info: ")
                parts = split(line, ' ')
                @test length(parts) == 4
                push!(dates, DateTime(strip(parts[3])[1:(end-1)]))
            end
        end
        @test length(dates) == 5
        @test dates[3] == dt_from_time
        @test dates[4] == testdt
        @test dates[5] == testdt
    end
end

function test_json_format()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)

        logger = RollingLogger(filepath, 2000, 3; format=:json)
        testdt = DateTime(2000, 1, 1, 1, 1, 1, 1)
        timenow = time()
        dt_from_time = Dates.unix2datetime(timenow)
        with_logger(logger) do
            @info("without_timestamp")
            @info("without_timestamp", testarg=1)
            @info("with_timestamp", time=timenow)
            @info("with_timestamp", time=testdt)
            @info("with_timestamp", time=testdt, testarg=1)
            @test isfile(filepath)
        end
        close(logger)

        dates = DateTime[]
        open(filepath) do readio
            while !eof(readio)
                try
                    entry = JSON.parse(readio)
                    push!(dates, DateTime(entry["metadata"]["time"]))
                catch ex
                    eof(readio) || rethrow()
                end
            end
        end

        @test length(dates) == 5
        @test dates[3] == dt_from_time
        @test dates[4] == testdt
        @test dates[5] == testdt
    end

    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)

        logger = RollingLogger(filepath, 20000, 3; format=:json)
        with_logger(logger) do
            for i in 1:4
                @info("log message $i", time=time(), randval=rand(Int))
            end
            with_logger(current_logger()) do
                @info("test nested with_logger", time=time())
            end
            @info rand(1000, 1000)
            @info(Vector{Bool})
            try
                error("test exception")
            catch ex
                @error("caught an exception", ex)
                @error("this is the exception with backtrace", exception=(ex,catch_backtrace()))
            end
            @warn("test other types", ptr1=Ptr{Nothing}(), ptr2=Ptr{Int}(10), sv=Core.svec(1,2,3), typ=String)
        end
        close(logger)

        open(filepath) do readio
            for idx in 1:4
                entry = JSON.parse(readio)
                @test entry["metadata"]["level"] == "Info"
                @test entry["message"] == "log message $idx"
            end
            entry = JSON.parse(readio)
            @test entry["metadata"]["level"] == "Info"
            @test entry["message"] == "test nested with_logger"

            entry = JSON.parse(readio)
            @test entry["metadata"]["level"] == "Info"
            @test length(entry["message"]) == (4*1024 + 3)

            entry = JSON.parse(readio)
            @test entry["metadata"]["level"] == "Info"
            @test endswith(entry["message"], "Array{Bool,1}") || startswith(entry["message"], "Vector{Bool}") # either "Array{Bool,1}" or "Vector{Bool} = Array{Bool,1} or Vector{Bool} (alias for...)"

            entry = JSON.parse(readio)
            @test entry["metadata"]["level"] == "Error"
            @test entry["message"] == "caught an exception"
            @test haskey(entry["keywords"], "ex")
            @test haskey(entry["keywords"]["ex"], "msg")
            @test entry["keywords"]["ex"]["msg"] == "test exception"

            entry = JSON.parse(readio)
            @test entry["metadata"]["level"] == "Error"
            @test entry["message"] == "this is the exception with backtrace"
            @test haskey(entry["keywords"], "exception")
            @test startswith(entry["keywords"]["exception"], "test exception\nStacktrace:")

            entry = JSON.parse(readio)
            @test entry["metadata"]["level"] == "Warn"
            @test entry["message"] == "test other types"
            @test haskey(entry["keywords"], "ptr1")
            @test haskey(entry["keywords"], "ptr2")
            @test haskey(entry["keywords"], "sv")
            @test haskey(entry["keywords"], "typ")
            @test entry["keywords"]["sv"] == [1,2,3]
            @test entry["keywords"]["typ"] == "String"
        end
    end
end

function test_size_limits()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)

        logger = RollingLogger(filepath, 2000, 3; format=:json, entry_size_limit=250+length(filepath))
        with_logger(logger) do
            @info("short msg")
            @info("short msg", v=1)
            @info("long msg", v="-"^100)
            @info("long msg " * "-"^100)
        end
        close(logger)

        open(filepath) do readio
            entry = JSON.parse(readio)
            @test entry["message"] == "short msg"
            @test !haskey(entry, "keywords")
            entry = JSON.parse(readio)
            @test entry["message"] == "short msg"
            @test entry["keywords"]["v"] == 1
            entry = JSON.parse(readio)
            @test entry["message"] == "long msg"
            @test !haskey(entry, "keywords")
            entry = JSON.parse(readio)
            @test !haskey(entry, "message")
            @test !haskey(entry, "keywords")
        end
    end
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)

        logger = RollingLogger(filepath, 2000, 3; format=:console, entry_size_limit=100)
        with_logger(logger) do
            @info("short msg")
            @info("short msg", v=1)
            @info("long msg", v="-"^100)
            @info("long msg " * "-"^100)
        end
        close(logger)
        filecontents = readlines(filepath)
        @test length(filecontents) == 8
    end
end

function test_exception_printing()
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)

        logger = RollingLogger(filepath, 2000, 3; format=:json)
        with_logger(logger) do
            try
                error("test exception")
            catch ex
                @error("caught exception", exception=(ex,catch_backtrace()))
            end
        end
        close(logger)
        open(filepath) do readio
            entry = JSON.parse(readio)
            lines = readlines(IOBuffer(entry["keywords"]["exception"]))
            @test length(lines) > 10
        end
    end
    mktempdir() do logdir
        filename = "test.log"
        filepath = joinpath(logdir, filename)

        logger = RollingLogger(filepath, 2000, 3; format=:console)
        with_logger(logger) do
            try
                error("test exception")
            catch ex
                @error("caught exception", exception=(ex,catch_backtrace()))
            end
        end
        close(logger)
        @test length(readlines(filepath)) > 10
    end
end

@testset "file writer" begin
    test_filewriter()
end

@testset "process streams" begin
    test_process_streams()
end

@testset "logger" begin
    test_logger()
    test_timestamp_handling()
    test_postrotate()
    test_json_format()
    test_size_limits()
    test_exception_printing()
end

