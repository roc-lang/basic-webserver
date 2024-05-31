extern crate proc_macro;

use core::panic;

use proc_macro::TokenStream;
use proc_macro2::Span;
use quote::quote;
use syn::{parse_macro_input, AttributeArgs, Ident, ItemFn, Lit, Meta, NestedMeta};

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
struct HostedFn {
    name: &'static str,
    arg_types: &'static [&'static str],
    ret_type: &'static str,
}

const ROC_HOSTED_FNS: &[HostedFn] = &[
    HostedFn {
        name: "sendRequest",
        arg_types: &["&roc_app::InternalRequest"],
        ret_type: "roc_app::InternalResponse",
    },
    HostedFn {
        name: "envVar",
        arg_types: &["&roc_std::RocStr"],
        ret_type: "roc_std::RocResult<roc_std::RocStr, ()>",
    },
    HostedFn {
        name: "envList",
        arg_types: &[],
        ret_type: "roc_std::RocList<(roc_std::RocStr, roc_std::RocStr)>",
    },
    HostedFn {
        name: "exePath",
        arg_types: &[],
        ret_type: "roc_std::RocResult<roc_std::RocList<u8>, ()>",
    },
    HostedFn {
        name: "setCwd",
        arg_types: &["&roc_std::RocList<u8>"],
        ret_type: "roc_std::RocResult<(), ()>",
    },
    HostedFn {
        name: "cwd",
        arg_types: &[],
        ret_type: "roc_std::RocList<u8>",
    },
    HostedFn {
        name: "stdoutLine",
        arg_types: &["&roc_std::RocStr"],
        ret_type: "()",
    },
    HostedFn {
        name: "stdoutWrite",
        arg_types: &["&roc_std::RocStr"],
        ret_type: "()",
    },
    HostedFn {
        name: "stdoutFlush",
        arg_types: &[],
        ret_type: "()",
    },
    HostedFn {
        name: "stderrLine",
        arg_types: &["&roc_std::RocStr"],
        ret_type: "()",
    },
    HostedFn {
        name: "stderrWrite",
        arg_types: &["&roc_std::RocStr"],
        ret_type: "()",
    },
    HostedFn {
        name: "stderrFlush",
        arg_types: &[],
        ret_type: "()",
    },
    HostedFn {
        name: "commandOutput",
        arg_types: &["&glue_manual::InternalCommand"],
        ret_type: "glue_manual::InternalOutput",
    },
    HostedFn {
        name: "commandStatus",
        arg_types: &["&glue_manual::InternalCommand"],
        ret_type: "roc_std::RocResult<(), glue_manual::InternalCommandErr>",
    },
    HostedFn {
        name: "posixTime",
        arg_types: &[],
        ret_type: "roc_std::U128",
    },
    HostedFn {
        name: "tcpConnect",
        arg_types: &["&roc_std::RocStr", "u16"],
        ret_type: "glue_manual::ConnectResult",
    },
    HostedFn {
        name: "tcpClose",
        arg_types: &["*mut std::io::BufReader<std::net::TcpStream>"],
        ret_type: "()",
    },
    HostedFn {
        name: "tcpReadUpTo",
        arg_types: &["usize", "*mut std::io::BufReader<std::net::TcpStream>"],
        ret_type: "glue_manual::ReadResult",
    },
    HostedFn {
        name: "tcpReadExactly",
        arg_types: &["usize", "*mut std::io::BufReader<std::net::TcpStream>"],
        ret_type: "glue_manual::ReadExactlyResult",
    },
    HostedFn {
        name: "tcpReadUntil",
        arg_types: &["u8", "*mut std::io::BufReader<std::net::TcpStream>"],
        ret_type: "glue_manual::ReadResult",
    },
    HostedFn {
        name: "tcpWrite",
        arg_types: &[
            "&roc_std::RocList<u8>",
            "*mut std::io::BufReader<std::net::TcpStream>",
        ],
        ret_type: "glue_manual::WriteResult",
    },
    HostedFn {
        name: "sleepMillis",
        arg_types: &["u64"],
        ret_type: "()",
    },
    HostedFn {
        name: "fileWriteUtf8",
        arg_types: &["&roc_std::RocList<u8>","&roc_std::RocStr"],
        ret_type: "roc_std::RocResult<(), glue_manual::WriteErr>",
    },
    HostedFn {
        name: "fileWriteBytes",
        arg_types: &["&roc_std::RocList<u8>","&roc_std::RocList<u8>"],
        ret_type: "roc_std::RocResult<(), glue_manual::WriteErr>",
    },
    HostedFn {
        name: "fileDelete",
        arg_types: &["&roc_std::RocList<u8>"],
        ret_type: "roc_std::RocResult<(), glue_manual::ReadErr>",
    },
    HostedFn {
        name: "fileReadBytes",
        arg_types: &["&roc_std::RocList<u8>"],
        ret_type: "roc_std::RocResult<roc_std::RocList<u8>, glue_manual::ReadErr>",
    },
    HostedFn {
        name: "dirList",
        arg_types: &["&roc_std::RocList<u8>"],
        ret_type: "roc_std::RocResult<roc_std::RocList<roc_std::RocList<u8>>, glue_manual::InternalDirReadErr>",
    },
    HostedFn {
        name: "sqliteExecute",
        arg_types: &["&roc_std::RocStr", "&roc_std::RocStr", "&roc_std::RocList<SQLiteBindings>"],
        ret_type: "roc_std::RocResult<RocList<RocList<glue_manual::SQLiteValue>>, SQLiteError>",
    },
    ];

fn find_hosted_fn_by_name(name: &str) -> Option<HostedFn> {
    for hosted in ROC_HOSTED_FNS.iter().copied() {
        if hosted.name == name {
            return Some(hosted);
        }
    }

    None
}

#[proc_macro_attribute]
pub fn roc_fn(args: TokenStream, input: TokenStream) -> TokenStream {
    // Parse the input tokens into a syntax tree
    let input_fn = parse_macro_input!(input as ItemFn);
    let args = parse_macro_input!(args as AttributeArgs);

    // Get the name from the attribute's arguments
    let name = match args.first() {
        Some(NestedMeta::Meta(Meta::NameValue(nv))) if nv.path.is_ident("name") => {
            if let Lit::Str(lit) = &nv.lit {
                lit.value()
            } else {
                panic!("Expected a string after `name=`");
            }
        }
        _ => panic!("Expected `name=\"...\"`"),
    };

    let hosted_fn = find_hosted_fn_by_name(&name.as_str()).unwrap_or_else(|| {
        panic!("The Roc platform which `roc glue` was run on does not have a hosted function by the name of {:?}", name);
    });

    let input_fn_name = &input_fn.sig.ident;

    // Generate the appropriate arg names and types, and return type,
    // using the types that were in the .roc file as the source of truth.
    let arg_names = (0..hosted_fn.arg_types.len())
        .into_iter()
        .map(|index| Ident::new(&format!("arg{index}"), Span::call_site()))
        .collect::<Vec<_>>();

    let arg_types: Vec<_> = hosted_fn
        .arg_types
        .iter()
        .zip(arg_names.iter())
        .map(|(arg_type, arg_name)| {
            let arg_type = arg_type
                .parse::<proc_macro2::TokenStream>()
                .expect("Failed to parse argument type");

            quote! { #arg_name: #arg_type }
        })
        .collect();

    let ret_type = hosted_fn
        .ret_type
        .parse::<proc_macro2::TokenStream>()
        .expect("Failed to parse return type");

    // Create the extern "C" function
    let output_fn_name = Ident::new(&format!("roc_fx_{}", name), Span::call_site());

    let gen = quote! {
        #input_fn

        #[no_mangle]
        pub extern "C" fn #output_fn_name(#(#arg_types),*) -> #ret_type {
            #input_fn_name(#(#arg_names),*)
        }
    };

    gen.into()
}
