platform "glue-stuff"
    requires {} { main : Http.Metadata } # TODO change to U16 for status code
    exposes []
    packages {}
    imports [Http]
    provides [mainForHost]

mainForHost : Http.Metadata
mainForHost = main
