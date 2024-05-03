module [deleteEmptyDir, deleteRecursive, list]

import Effect
import Task exposing [Task]
import InternalTask
import Path exposing [Path]
import InternalPath
import InternalError

ReadErr : InternalError.InternalDirReadErr

DeleteErr : InternalError.InternalDirDeleteErr

## Lists the files and directories inside the directory.
list : Path -> Task (List Path) ReadErr
list = \path ->
    effect = Effect.map (Effect.dirList (InternalPath.toBytes path)) \result ->
        when result is
            Ok entries -> Ok (List.map entries InternalPath.fromOsBytes)
            Err err -> Err err

    InternalTask.fromEffect effect

## Deletes a directory if it's empty.
deleteEmptyDir : Path -> Task {} DeleteErr

## Recursively deletes the directory as well as all files and directories inside it.
deleteRecursive : Path -> Task {} DeleteErr
