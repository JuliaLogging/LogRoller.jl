using LogRoller, Test, Logging

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

        # roll twice
        with_logger(logger) do
            for count in 1:10
                @info(logstr)
            end
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
        with_logger(logger) do
            for count in 1:20
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
    end
end

test_filewriter()
test_logger()
