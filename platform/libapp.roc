app [main] { pf: platform "main.roc" }

import pf.Task

main = \_ -> Task.ok { status: 200, headers: [], body: [] }
