platform "private-sink-spike"
    requires {
        make! : U64 => Sse.Stream
    }
    exposes [Sse]
    packages {}
    provides {
        "roc_private_sink_make": make_for_host!,
        "roc_private_sink_advance": advance_for_host!,
        "roc_private_sink_drop": drop_for_host!,
    }
    hosted {
        "hosted_private_sink_publish": Host.publish!,
    }
    targets: {
        inputs_dir: "targets/",
        x64musl: { inputs: [app], output: Archive },
    }

import Host
import Sse

make_for_host! : U64 => Sse.Stream
make_for_host! = make!

advance_for_host! : Sse.Stream, U64, U64 => Sse.Stream
advance_for_host! = |stream, wake, raw_sink|
    Sse.advance_for_host!(stream, wake, Host.sink_from_host(raw_sink))

drop_for_host! : Sse.Stream => {}
drop_for_host! = Sse.drop_for_host!
