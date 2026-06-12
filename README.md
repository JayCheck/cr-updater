# Brave component update server written in Go

`go-update` implements a [component update server](https://developer.chrome.com/apps/autoupdate) for use in brave-core written in Go.

The intended audience for this server is all users of brave-core.

The server is only intended to support a small number of extensions that Brave handles ourselves.

The component update server supports 2 types of requests both at the same endpoint `/extensions`

1) The `POST /extensions` endpoint uses an XML schema for the request and the response.  Samples can be found in the tests.
2) The `GET /extensions` endpoint uses URL query parameters and responds with a similar XML schema. Samples can also be found in the tests.

This server is compatible with Google's component update server, so it is a drop-in replacement to handle the requests coming from Chromium.

When there is only a single extension requested, and if we do not support the extension ourselves, we will redirect the request to Google's component updater to handle the request.

This server also serves as a filter so Brave can blacklist any extension before it has a chance to redirect to Google's component updater.

## Runbook
https://github.com/brave/devops/tree/master/docs/runbooks/go-updater

## Dependencies

Go 1.25.

## Run lint:

Install `golangci-lint` if you don't already have it:

`go get github.com/golangci/golangci-lint/cmd/golangci-lint`

Then:

`make lint`

## Run tests:

`make test`

## Build go-update:

`make build`

## Run go-update:

`./main`

## Run local Triple Banana component updater on Termux:

```sh
pkg install -y git
git clone https://github.com/JayCheck/cr-updater.git
cd cr-updater
scripts/setup-termux.sh --run
```

The local updater listens on `http://127.0.0.1:8000/update2/json` by
default. Use `GO_UPDATE_PORT`, `GO_UPDATE_HOST`, or `GO_UPDATE_ADDR` to
override the bind address. The setup script disables unknown-application
redirects so Chromium-owned component checks finish locally during PoC tests.
Use `scripts/setup-termux.sh --run --redirect-google` to redirect unknown
Chromium-owned components to `update.googleapis.com` instead.

## Triple Banana CRX hosting

The Triple Banana PoC CRX is published under `docs/release/` so GitHub Pages can
serve it at:

```text
https://jaycheck.github.io/cr-updater/release/jebgalgnebhfojomionfpkfelancnnkf/extension_1_0_1.crx
```

When running the updater server for the public APK test, keep the update check
server behind nginx and return GitHub Pages URLs for CRX downloads:

```sh
GO_UPDATE_ADDR=127.0.0.1:8000 \
GO_UPDATE_USE_STATIC_EXTENSIONS=true \
LOCAL_CRX_DIR=$PWD/local_crx \
S3_EXTENSIONS_BUCKET_URL=https://jaycheck.github.io/cr-updater \
GO_UPDATE_REDIRECT_UNKNOWN_APPLICATIONS=false \
LOG_REQUEST=true \
GOTOOLCHAIN=local go run .
```
