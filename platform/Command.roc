module [
    Command,
    Output,
    new,
    arg,
    args,
    env,
    envs,
    clearEnvs,
    status,
    output,
]

import Task exposing [Task]
import InternalTask
import InternalCommand
import Effect

## Represents a command to be executed in a child process.
## ```
## {
##     status : Result {} [ExitCode I32, KilledBySignal, IOError Str],
##     stdout : List U8,
##     stderr : List U8,
## }
## ```
Command := InternalCommand.InternalCommand

## Errors from executing a command.
## ```
## [
##     ExitCode I32,
##     KilledBySignal,
##     IOError Str,
## ]
## ```
Error : InternalCommand.InternalCommandErr

## Represents the output of a command.
## ```
## {
##     status : Result {} [ExitCode I32, KilledBySignal, IOError Str],
##     stdout : List U8,
##     stderr : List U8,
## }
## ```
Output : InternalCommand.InternalOutput

## Create a new command to execute the given program in a child process.
##
## ```
## Command.new "sqlite3" # Execute "sqlite3" program
## ```
new : Str -> Command
new = \program ->
    @Command {
        program,
        args: [],
        envs: [],
        clearEnvs: Bool.false,
    }

## Add a single argument to the command.
##
## ```
## # Represent the command "ls -l"
## Command.new "ls"
## |> Command.arg "-l"
## ```
arg : Command, Str -> Command
arg = \@Command cmd, value ->
    @Command
        { cmd &
            args: List.append cmd.args value,
        }

## Add multiple arguments to the command.
##
## ```
## # Represent the command "ls -l -a"
## Command.new "ls"
## |> Command.args ["-l", "-a"]
## ```
##
args : Command, List Str -> Command
args = \@Command cmd, values ->
    @Command
        { cmd &
            args: List.concat cmd.args values,
        }

## Add a single environment variable to the command.
##
## ```
## # Run "env" and add the environment variable "FOO" with value "BAR"
## Command.new "env"
## |> Command.env "FOO" "BAR"
## ```
##
env : Command, Str, Str -> Command
env = \@Command cmd, key, value ->
    @Command
        { cmd &
            envs: List.concat cmd.envs [key, value],
        }

## Add multiple environment variables to the command.
##
## ```
## # Run "env" and add the variables "FOO" and "BAZ"
## Command.new "env"
## |> Command.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
## ```
##
envs : Command, List (Str, Str) -> Command
envs = \@Command cmd, keyValues ->
    values = keyValues |> List.joinMap \(key, value) -> [key, value]
    @Command
        { cmd &
            envs: List.concat cmd.envs values,
        }

## Clear all environment variables, and prevent inheriting from parent, only
## the environment variables provided to command are available to the child.
##
## ```
## # Represents "env" with only "FOO" environment variable set
## Command.new "env"
## |> Command.clearEnvs
## |> Command.env "FOO" "BAR"
## ```
##
clearEnvs : Command -> Command
clearEnvs = \@Command cmd ->
    @Command { cmd & clearEnvs: Bool.true }

## Execute command and capture stdout and stderr
##
## > Stdin is not inherited from the parent and any attempt by the child process
## > to read from the stdin stream will result in the stream immediately closing.
## ```
## output <-
##     Command.new "sqlite3"
##     |> Command.arg dbPath
##     |> Command.arg ".mode json"
##     |> Command.arg "SELECT id, task, status FROM todos;"
##     |> Command.output
##     |> Task.await
##
## when output.status is
##     Ok {} -> jsonResponse output.stdout
##     Err _ -> byteResponse 500 output.stderr
## ```
output : Command -> Task Output *
output = \@Command cmd ->
    Effect.commandOutput (Box.box cmd)
    |> Effect.map (\out -> Ok out)
    |> InternalTask.fromEffect

## Execute command and inheriting stdin, stdout and stderr from parent
## ```
## # Log request date, method and url using echo program
## date <- Utc.now |> Task.map Utc.toIso8601Str |> Task.await
## result <-
##     Command.new "echo"
##     |> Command.arg "$(date) $(Http.methodToStr req.method) $(req.url)"
##     |> Command.status
##     |> Task.attempt
##
## when result is
##     Ok {} -> respond "Command succeeded"
##     Err (ExitCode code) -> respond "Command exited with code $(Num.toStr code)"
##     Err (KilledBySignal) -> respond "Command was killed by signal"
##     Err (IOError str) -> respond "IO Error: $(str)"
## ```
status : Command -> Task {} Error
status = \@Command cmd ->
    Effect.commandStatus (Box.box cmd)
    |> InternalTask.fromEffect
