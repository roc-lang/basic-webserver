module [deleteEmptyDir, deleteRecursive, list]

import Path exposing [Path]
import InternalPath
import InternalError
import PlatformTask

ReadErr : InternalError.InternalDirReadErr

DeleteErr : InternalError.InternalDirDeleteErr

## Lists the files and directories inside the directory.
list : Path -> Task (List Path) ReadErr
list = \path ->
    PlatformTask.dirList (InternalPath.toBytes path)
    |> Task.map \entries -> List.map entries InternalPath.fromOsBytes

## Deletes a directory if it's empty.
deleteEmptyDir : Path -> Task {} DeleteErr

## Recursively deletes the directory as well as all files and directories inside it.
deleteRecursive : Path -> Task {} DeleteErr
