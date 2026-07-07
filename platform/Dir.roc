import IOErr exposing [IOErr]
import Host
import InternalPath
import Path

Dir := [].{
    ## Creates a new, empty directory at the provided path.
    ##
    ## If the parent directories do not exist, they will not be created.
    ## Use [Dir.create_all!] to create parent directories as needed.
    create! : Str => Try({}, [DirErr(IOErr), ..])
    create! = |path|
        match Host.dir_create!(path) {
            Ok(done) => Ok(done)
            Err(DirErr(err)) => Err(DirErr(err))
        }

    ## Creates a new, empty directory at the provided path, including any parent directories.
    ##
    ## If the directory already exists, this will succeed without error.
    create_all! : Str => Try({}, [DirErr(IOErr), ..])
    create_all! = |path|
        match Host.dir_create_all!(path) {
            Ok(done) => Ok(done)
            Err(DirErr(err)) => Err(DirErr(err))
        }

    ## Deletes an empty directory.
    ##
    ## Fails if the directory is not empty. Use [Dir.delete_all!] to delete
    ## a directory and all its contents.
    delete_empty! : Str => Try({}, [DirErr(IOErr), ..])
    delete_empty! = |path|
        match Host.dir_delete_empty!(path) {
            Ok(done) => Ok(done)
            Err(DirErr(err)) => Err(DirErr(err))
        }

    ## Deletes a directory and all of its contents recursively.
    ##
    ## Use with caution!
    delete_all! : Str => Try({}, [DirErr(IOErr), ..])
    delete_all! = |path|
        match Host.dir_delete_all!(path) {
            Ok(done) => Ok(done)
            Err(DirErr(err)) => Err(DirErr(err))
        }

    ## Lists the contents of a directory.
    ##
    ## Returns the paths of all files and directories within the specified directory.
    list! : Str => Try(List(Path.Path), [DirErr(IOErr), ..])
    list! = |path|
        match Host.dir_list!(path) {
            Ok(paths) => Ok(paths.map(InternalPath.from_host_raw))
            Err(DirErr(err)) => Err(DirErr(err))
        }
}
