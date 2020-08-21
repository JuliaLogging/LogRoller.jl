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

function test_pipelined_tee()
    mktempdir() do logdir
        filename1 = "test1.log"
        filename2 = "test2.log"
        filepath1 = joinpath(logdir, filename1)
        filepath2 = joinpath(logdir, filename2)
        @test !isfile(filepath1)
        @test !isfile(filepath2)

        logger1io = open(filepath1, "w+")
        logger1 = SimpleLogger(logger1io)
        logger2 = RollingFileWriterTee(filepath2, 1000, 3, logger1, Logging.Info)

        julia = joinpath(Sys.BINDIR, "julia")
        cmd = pipeline(`$julia -e 'for i in 1:5 println(string("hello",i)) end; flush(stdout)'`; stdout=logger2, stderr=logger2)
        run(cmd)

        close(logger2)
        close(logger1io)

        @test isfile(filepath1)
        @test isfile(filepath2)
        @test (2*length(readlines(filepath2))) == length(readlines(filepath1)) # Julia logger entry will be two lines for every raw message
        if !Sys.iswindows()    # streams do not seem to be flushed cleanly on Windows
            @test length(readlines(filepath2)) == 5
        end
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

        @test io.procstream !== nothing
        @test io.procstreamer !== nothing
        @test !istaskdone(io.procstreamer)

        close(io)
        @test io.procstream === nothing
        @test io.procstreamer === nothing
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

@testset "file writer" begin
    test_filewriter()
end
@testset "pipelined tee" begin
    test_pipelined_tee()
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
end
