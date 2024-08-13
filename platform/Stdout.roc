module [line, write, flush]

import PlatformTask

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
## followed by a newline.
##
## > To write to `stdout` without the newline, see [Stdout.write].
line : Str -> Task {} *
line = PlatformTask.stdoutLine

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
##
## Note that many terminals will not actually display strings that are written to them until they receive a newline,
## so this may appear to do nothing until you write a newline!
##
## > To write to `stdout` with a newline at the end, see [Stdout.line].
write : Str -> Task {} *
write = PlatformTask.stdoutWrite

## Flush the [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
## This will cause any buffered output to be written out. This is typically to
## the terminal but may be captured and written to a file.
##
## This may fail if the buffered output could not be written due to I/O
## errors or EOF being reached.
flush : Task {} *
flush = PlatformTask.stdoutFlush
