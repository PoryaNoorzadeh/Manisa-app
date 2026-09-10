package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/application"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/config"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/httpapi"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/storage/sqlite"
)

func main() {
	cfg := config.Load()
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	db, err := sqlite.Open(cfg.DatabasePath)
	if err != nil {
		logger.Error("open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	store := sqlite.NewStore(db)
	app := application.New(store)

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           httpapi.NewRouter(logger, db, app),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		logger.Info("manisa-core started", "addr", cfg.HTTPAddr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("http server", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		logger.Error("graceful shutdown", "error", err)
	}
}
