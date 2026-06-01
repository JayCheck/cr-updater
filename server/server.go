// Package server implements the web server for extension update requests
package server

import (
	"context"
	"net"
	"net/http"
	_ "net/http/pprof" // pprof magic
	"os"
	"strconv"
	"strings"
	"time"

	batware "github.com/brave-intl/bat-go/middleware"
	"github.com/brave/go-update/controller"
	"github.com/brave/go-update/extension"
	"github.com/brave/go-update/logger"
	"github.com/brave/go-update/server/middleware"
	"github.com/getsentry/sentry-go"
	"github.com/go-chi/chi/v5"
	chiware "github.com/go-chi/chi/v5/middleware"
)

func setupRouter(ctx context.Context, testRouter bool) (context.Context, *chi.Mux) {
	r := chi.NewRouter()
	// It's not efficient to compress objects smaller than 1KB
	//
	// Ref: https://github.com/klauspost/compress/blob/1a8c0e48e1fa4245694103fc47721c83a9135588/gzhttp/compress.go#L50-L55
	r.Use(middleware.OptimizedCompress(5, 1024, "application/json", "application/xml"))
	r.Use(chiware.Heartbeat("/"))
	r.Use(chiware.Timeout(60 * time.Second))

	shouldLog, ok := os.LookupEnv("LOG_REQUEST")
	if ok && shouldLog == "true" {
		r.Use(logger.RequestLoggerMiddleware())
	}

	extensions := extension.OfferedExtensions
	useStatic := useStaticExtensions()
	if useStatic {
		controller.AllExtensionsMap.StoreExtensions(&extensions)
	}

	extensionsRouter := controller.ExtensionsRouter(extensions, testRouter || useStatic)
	r.Post("/update2/json", controller.UpdateExtensions)
	r.Post("/update2", controller.UpdateExtensions)
	r.Mount("/extensions", extensionsRouter)

	if localCRXDir := os.Getenv("LOCAL_CRX_DIR"); localCRXDir != "" {
		r.Handle("/release/*", http.StripPrefix("/release/", http.FileServer(http.Dir(localCRXDir))))
	}

	return ctx, r
}

func useStaticExtensions() bool {
	if value, ok := os.LookupEnv("GO_UPDATE_USE_STATIC_EXTENSIONS"); ok {
		enabled, err := strconv.ParseBool(value)
		return err == nil && enabled
	}

	return os.Getenv("LOCAL_CRX_DIR") != ""
}

func listenAddr() string {
	if value := os.Getenv("GO_UPDATE_ADDR"); value != "" {
		return value
	}

	if value := os.Getenv("PORT"); value != "" {
		if strings.HasPrefix(value, ":") {
			return value
		}
		return ":" + value
	}

	return ":8192"
}

func listenURL(addr string) string {
	if strings.HasPrefix(addr, ":") {
		return "http://localhost" + addr
	}

	return "http://" + addr
}

// StartServer starts the component updater server.
func StartServer() {
	serverCtx, log := logger.Setup(context.Background())
	log.Info("Starting server", "prefix", "main")

	go func() {
		// setup metrics on another non-public port 9090
		// nosemgrep: go.lang.security.audit.net.pprof.pprof-debug-exposure
		err := http.ListenAndServe(":9090", batware.Metrics())
		if err != nil {
			sentry.CaptureException(err)
			logger.Panic(log, "Metrics HTTP server failed to start", err)
		}
	}()

	// Add profiling flag to enable profiling routes.
	if on, _ := strconv.ParseBool(os.Getenv("PPROF_ENABLED")); on {
		// pprof attaches routes to default serve mux
		// host:6061/debug/pprof/
		go func() {
			if err := http.ListenAndServe(":6061", http.DefaultServeMux); err != nil {
				log.Error("Server failed to start", "error", err)
			}
		}()
	}

	serverCtx, r := setupRouter(serverCtx, false)
	addr := listenAddr()
	log.Info("Starting HTTP server", "url", listenURL(addr))

	srv := http.Server{
		Addr:        addr,
		Handler:     r,
		BaseContext: func(_ net.Listener) context.Context { return serverCtx },
	}
	err := srv.ListenAndServe()
	if err != nil {
		sentry.CaptureException(err)
		logger.Panic(log, "Server failed to start", err)
	}
}
