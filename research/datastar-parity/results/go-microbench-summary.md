| Benchmark | n | ns/op median [min, max] | B/op median | allocs/op median | wire bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| `Finite/identity/256` | 5 | 1299.0 [1248.0, 1326.0] | 6674 | 26 | 305.00 |
| `Finite/brotli-idiomatic/256` | 5 | 773997.0 [758902.0, 780949.0] | 8292558 | 182 | 95.00 |
| `Finite/brotli-equivalent-q4-w18/256` | 5 | 122792.0 [122627.0, 127426.0] | 1113264 | 64 | 105.00 |
| `Finite/identity/4096` | 5 | 1543.0 [1533.0, 1587.0] | 11296 | 26 | 4145.00 |
| `Finite/brotli-idiomatic/4096` | 5 | 759129.0 [709380.0, 824458.0] | 8368316 | 179 | 99.00 |
| `Finite/brotli-equivalent-q4-w18/4096` | 5 | 114365.0 [109829.0, 130389.0] | 1186841 | 65 | 108.00 |
| `Finite/identity/65536` | 5 | 8390.0 [8138.0, 13823.0] | 86448 | 26 | 65585.00 |
| `Finite/brotli-idiomatic/65536` | 5 | 857809.0 [832754.0, 872653.0] | 17830634 | 170 | 100.00 |
| `Finite/brotli-equivalent-q4-w18/65536` | 5 | 279962.0 [266334.0, 288724.0] | 2745456 | 76 | 110.00 |
| `Persistent/identity/256` | 5 | 150.7 [143.1, 157.0] | 544 | 6 | 305.00 |
| `Persistent/brotli-idiomatic/256` | 5 | 2860.0 [2825.0, 2941.0] | 631 | 6 | 11.00 |
| `Persistent/brotli-equivalent-q4-w18/256` | 5 | 2813.0 [2779.0, 2855.0] | 558 | 6 | 11.00 |
| `Persistent/identity/4096` | 5 | 473.0 [462.6, 475.1] | 5141 | 6 | 4145.00 |
| `Persistent/brotli-idiomatic/4096` | 5 | 9039.0 [9031.0, 9314.0] | 5407 | 6 | 13.00 |
| `Persistent/brotli-equivalent-q4-w18/4096` | 5 | 11331.0 [10996.0, 11502.0] | 5226 | 6 | 13.00 |
