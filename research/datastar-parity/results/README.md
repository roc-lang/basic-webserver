# Preliminary Go reference results

These results were captured on 2026-08-01 from harness commit `9ae99ce` with:

```sh
GO_BIN=/tmp/go1.26.5/bin/go ../capture_environment.sh
GOTOOLCHAIN=local /tmp/go1.26.5/bin/go test \
  -run '^$' \
  -bench 'BenchmarkOfficialSDK' \
  -benchmem \
  -benchtime=300ms \
  -count=5 .
python3 ../summarize_benchmarks.py
```

`go-microbench.txt` is the raw Go output. The summary contains medians and the
observed range, not statistical comparisons between implementations. These are
in-process SDK framing/codec measurements and must not be presented as HTTP or
browser performance.
