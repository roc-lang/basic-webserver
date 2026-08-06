app [make!] { pf: platform "./platform/main.roc" }

import pf.Sse

make! = |events|
    Sse.unfold!(
        { remaining: events, sequence: 0 },
        |state, wake| {
            if state.remaining == 0 {
                { item: [], kind: 1, state, wait_millis: 0 }
            } else {
                {
                    item: [100, 97, 116, 97, 58, 32, 111, 107, 10, 10],
                    kind: 0,
                    state: {
                        remaining: state.remaining - 1,
                        sequence: state.sequence + wake + 1,
                    },
                    wait_millis: state.sequence % 17,
                }
            }
        },
    )
