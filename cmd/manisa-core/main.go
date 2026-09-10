package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/adapters/matterjs"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/application"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/auth"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/config"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/discovery"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/httpapi"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/storage/sqlite"
)

func main() {
	cfg, err := config.Load()
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err != nil {
		logger.Error("load configuration", "error", err)
		os.Exit(1)
	}

	db, err := sqlite.Open(cfg.DatabasePath)
	if err != nil {
		logger.Error("open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	store := sqlite.NewStore(db)
	matterController := matterjs.New(cfg.MatterWSURL)
	app := application.New(store, matterController)
	authService := auth.New(store, cfg.PairingCode)

	runtimeCtx, runtimeCancel := context.WithCancel(context.Background())
	defer runtimeCancel()
	go runMatterEvents(runtimeCtx, logger, matterController, app)

	mdnsAdvertiser, err := discovery.Start(cfg.HTTPAddr)
	if err != nil {
		logger.Warn("mDNS advertisement unavailable", "error", err)
	} else {
		defer mdnsAdvertiser.Close()
		logger.Info("mDNS advertisement started", "service", discovery.ServiceType)
	}

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           httpapi.NewRouter(logger, db, app, authService),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		logger.Info("manisa-core started", "addr", cfg.HTTPAddr, "matter_ws_url", cfg.MatterWSURL)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("http server", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	runtimeCancel()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		logger.Error("graceful shutdown", "error", err)
	}
}

func runMatterEvents(ctx context.Context, logger *slog.Logger, source matter.EventSource, app *application.Service) {
	backoff := time.Second
	const maxBackoff = 30 * time.Second

	for {
		started := time.Now()
		err := source.Listen(ctx, app.ApplyMatterAttribute)
		if ctx.Err() != nil {
			return
		}
		logger.Warn("matter event stream disconnected", "error", err, "retry_in", backoff)

		if time.Since(started) > time.Minute {
			backoff = time.Second
		}

		timer := time.NewTimer(backoff)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
		if backoff < maxBackoff {
			backoff *= 2
			if backoff > maxBackoff {
				backoff = maxBackoff
			}
		}
	}
}
