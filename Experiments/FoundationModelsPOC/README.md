# Foundation Models adaptation POC

An isolated, macOS 27 experiment. Run its reproducible offline gate from the repository root:

```sh
swift test --package-path Experiments/FoundationModelsPOC
```

`swift run --package-path Experiments/FoundationModelsPOC foundation-models-probe --help`
lists the intended DeepSeek, Google, and Anthropic live cases. The package links the
macOS 27 Foundation Models provider surface, but live transport executor conformance
and provider calls are intentionally unrecorded until credentials are supplied; no
credentials are read or logged by the offline suite.
