# artak-srs

`artak-srs` is a short-lived SRS-to-JSON conversion tool for the Xray routing
backend. It does not run a sing-box proxy or take part in packet forwarding.

It uses the SRS reader from `github.com/sagernet/sing-box` v1.13.4. The helper
and its dependency are distributed under GPL-3.0-or-later; retain the source,
dependency metadata and license notices when distributing compiled binaries.

```sh
artak-srs input.srs output.json
```

The current Xray importer can preserve positive domain and IP list matches.
The tool rejects unsupported logical, inverted, source, port, AdGuard and
combined domain/IP conditions instead of silently changing their meaning.
The router still rejects oversized lists; `.srs` conversion requires either
this helper or a valid existing conversion cache.

For the Cudy WR3000U, compile with Go using `GOOS=linux GOARCH=arm64
CGO_ENABLED=0`. Release automation builds the ARM64 binary and a SHA-256
checksum alongside the OpenWrt packages. It is not installed automatically
by the upstream installer yet.
