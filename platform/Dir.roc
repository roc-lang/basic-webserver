import IOErr exposing [IOErr]
import Host

Dir := [].{
    ## Creates a new, empty directory at the provided path.
    ##
    ## If the parent directories do not exist, they will not be created.
    ## Use [Dir.create_all!] to create parent directories as needed.
    create! : Str => Try({}, [DirErr(IOErr), ..])
    create! = |path| Ok(Host.dir_create!(path)?)

    ## Creates a new, empty directory at the provided path, including any parent directories.
    ##
    ## If the directory already exists, this will succeed without error.
    create_all! : Str => Try({}, [DirErr(IOErr), ..])
    create_all! = |path| Ok(Host.dir_create_all!(path)?)

    ## Deletes an empty directory.
    ##
    ## Fails if the directory is not empty. Use [Dir.delete_all!] to delete
    ## a directory and all its contents.
    delete_empty! : Str => Try({}, [DirErr(IOErr), ..])
    delete_empty! = |path| Ok(Host.dir_delete_empty!(path)?)

    ## Deletes a directory and all of its contents recursively.
    ##
    ## Use with caution!
    delete_all! : Str => Try({}, [DirErr(IOErr), ..])
    delete_all! = |path| Ok(Host.dir_delete_all!(path)?)

    ## Lists the contents of a directory.
    ##
    ## Returns the paths of all files and directories within the specified directory.
    ##
    ## TODO: This temporarily returns lossy Str paths. When the vendored Path
    ## subset is replaced by roc-lang/path, return byte-preserving Path values.
    list! : Str => Try(List(Str), [DirErr(IOErr), ..])
    list! = |path| Ok(Host.dir_list!(path)?)
}
