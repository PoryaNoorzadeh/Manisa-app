package httpapi

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/application"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/auth"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

type createHomeRequest struct {
	Name string `json:"name"`
}

type createRoomRequest struct {
	HomeID string `json:"homeId"`
	Name   string `json:"name"`
}

type createDeviceRequest struct {
	HomeID      string  `json:"homeId"`
	RoomID      *string `json:"roomId,omitempty"`
	Name        string  `json:"name"`
	ProductType string  `json:"productType"`
	Transport   string  `json:"transport"`
}

type pairRequest struct {
	Code       string `json:"code"`
	ClientName string `json:"clientName"`
}

type commissionMatterRequest struct {
	HomeID        string  `json:"homeId"`
	RoomID        *string `json:"roomId,omitempty"`
	Name          string  `json:"name"`
	ProductType   string  `json:"productType"`
	Transport     string  `json:"transport"`
	SetupPayload  string  `json:"setupPayload"`
	WiFiSSID      string  `json:"wifiSsid,omitempty"`
	WiFiPassword  string  `json:"wifiPassword,omitempty"`
	ThreadDataset string  `json:"threadDataset,omitempty"`
	NetworkOnly   bool    `json:"networkOnly,omitempty"`
}

type deviceCommandRequest struct {
	Endpoint   uint16         `json:"endpoint"`
	Capability string         `json:"capability"`
	Action     string         `json:"action"`
	Params     map[string]any `json:"params,omitempty"`
}

func NewRouter(logger *slog.Logger, db *sql.DB, app *application.Service, authServices ...*auth.Service) http.Handler {
	mux := http.NewServeMux()
	var authService *auth.Service
	if len(authServices) > 0 {
		authService = authServices[0]
	}

	mux.HandleFunc("GET /health/live", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "service": "manisa-core"})
	})

	mux.HandleFunc("GET /health/ready", func(w http.ResponseWriter, r *http.Request) {
		if err := db.PingContext(r.Context()); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]any{"status": "not_ready"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"status": "ready"})
	})

	if authService != nil {
		mux.HandleFunc("POST /api/v1/pair", func(w http.ResponseWriter, r *http.Request) {
			var req pairRequest
			if err := decodeJSON(w, r, &req); err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_json"})
				return
			}
			client, token, err := authService.Pair(r.Context(), req.Code, req.ClientName)
			if err != nil {
				writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "pairing_rejected"})
				return
			}
			writeJSON(w, http.StatusCreated, map[string]any{"client": client, "token": token})
		})
	}

	mux.HandleFunc("GET /api/v1/system", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"name":       "Manisa Core",
			"apiVersion": "v1",
			"localFirst": true,
			"time":       time.Now().UTC().Format(time.RFC3339),
		})
	})

	mux.HandleFunc("GET /api/v1/events", func(w http.ResponseWriter, r *http.Request) {
		serveEvents(w, r, app)
	})

	mux.HandleFunc("GET /api/v1/device-types", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, app.ListDeviceTypes())
	})

	mux.HandleFunc("GET /api/v1/devices/{deviceID}/descriptor", func(w http.ResponseWriter, r *http.Request) {
		descriptor, err := app.DeviceDescriptor(r.Context(), r.PathValue("deviceID"))
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, descriptor)
	})

	mux.HandleFunc("GET /api/v1/devices/{deviceID}/state", func(w http.ResponseWriter, r *http.Request) {
		states, err := app.DeviceStates(r.Context(), r.PathValue("deviceID"))
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, states)
	})

	mux.HandleFunc("GET /api/v1/homes", func(w http.ResponseWriter, r *http.Request) {
		homes, err := app.ListHomes(r.Context())
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, homes)
	})

	mux.HandleFunc("POST /api/v1/homes", func(w http.ResponseWriter, r *http.Request) {
		var req createHomeRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_json"})
			return
		}
		home, err := app.CreateHome(r.Context(), req.Name)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, home)
	})

	mux.HandleFunc("GET /api/v1/rooms", func(w http.ResponseWriter, r *http.Request) {
		rooms, err := app.ListRooms(r.Context(), r.URL.Query().Get("homeId"))
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, rooms)
	})

	mux.HandleFunc("POST /api/v1/rooms", func(w http.ResponseWriter, r *http.Request) {
		var req createRoomRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_json"})
			return
		}
		room, err := app.CreateRoom(r.Context(), req.HomeID, req.Name)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, room)
	})

	mux.HandleFunc("GET /api/v1/devices", func(w http.ResponseWriter, r *http.Request) {
		devices, err := app.ListDevices(r.Context(), r.URL.Query().Get("homeId"))
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, devices)
	})

	mux.HandleFunc("POST /api/v1/devices", func(w http.ResponseWriter, r *http.Request) {
		var req createDeviceRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_json"})
			return
		}
		device, err := app.CreateDevice(r.Context(), req.HomeID, req.Name, req.ProductType, req.Transport, req.RoomID)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, device)
	})

	mux.HandleFunc("POST /api/v1/matter/commission", func(w http.ResponseWriter, r *http.Request) {
		var req commissionMatterRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_json"})
			return
		}
		device, err := app.CommissionDevice(r.Context(), application.CommissionDeviceInput{
			HomeID: req.HomeID, RoomID: req.RoomID, Name: req.Name, ProductType: req.ProductType,
			Transport: req.Transport, SetupPayload: req.SetupPayload, WiFiSSID: req.WiFiSSID,
			WiFiPassword: req.WiFiPassword, ThreadDataset: req.ThreadDataset, NetworkOnly: req.NetworkOnly,
		})
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, device)
	})

	mux.HandleFunc("POST /api/v1/devices/{deviceID}/commands", func(w http.ResponseWriter, r *http.Request) {
		var req deviceCommandRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_json"})
			return
		}
		if err := app.ExecuteDeviceCommand(r.Context(), r.PathValue("deviceID"), application.DeviceCommandInput{
			Endpoint: req.Endpoint, Capability: req.Capability, Action: req.Action, Params: req.Params,
		}); err != nil {
			writeError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})

	var handler http.Handler = mux
	if authService != nil {
		handler = requireLocalAuth(authService, mux)
	}
	return requestLogger(logger, handler)
}

func requireLocalAuth(authService *auth.Service, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/health/") || r.URL.Path == "/api/v1/pair" {
			next.ServeHTTP(w, r)
			return
		}
		header := strings.TrimSpace(r.Header.Get("Authorization"))
		if !strings.HasPrefix(header, "Bearer ") {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
			return
		}
		if _, err := authService.Authenticate(r.Context(), strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))); err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func serveEvents(w http.ResponseWriter, r *http.Request, app *application.Service) {
	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	defer conn.CloseNow()

	ctx := conn.CloseRead(context.Background())
	events, unsubscribe := app.SubscribeEvents(128)
	defer unsubscribe()

	for {
		select {
		case <-ctx.Done():
			return
		case event := <-events:
			writeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			err := wsjson.Write(writeCtx, conn, event)
			cancel()
			if err != nil {
				return
			}
		}
	}
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}

func writeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, application.ErrInvalidInput):
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_input"})
	case errors.Is(err, application.ErrUnsupportedCapability):
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "unsupported_capability"})
	case errors.Is(err, application.ErrDeviceNotCommissioned):
		writeJSON(w, http.StatusConflict, map[string]any{"error": "device_not_commissioned"})
	case errors.Is(err, domain.ErrNotFound):
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "not_found"})
	default:
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "internal_error"})
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func requestLogger(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		logger.Info("http request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})
}
