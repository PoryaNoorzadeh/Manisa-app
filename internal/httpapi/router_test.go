package httpapi

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/application"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/storage/sqlite"
)

func newTestRouter(t *testing.T) http.Handler {
	t.Helper()
	db, err := sqlite.Open(t.TempDir() + "/manisa.db")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	store := sqlite.NewStore(db)
	app := application.New(store)
	return NewRouter(slog.New(slog.NewTextHandler(os.Stdout, nil)), db, app)
}

func TestLiveness(t *testing.T) {
	router := newTestRouter(t)
	req := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	res := httptest.NewRecorder()
	router.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.Code)
	}
}

func TestCreateAndListHome(t *testing.T) {
	router := newTestRouter(t)

	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/homes", strings.NewReader(`{"name":"My Home"}`))
	createRes := httptest.NewRecorder()
	router.ServeHTTP(createRes, createReq)
	if createRes.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", createRes.Code, createRes.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/homes", nil)
	listRes := httptest.NewRecorder()
	router.ServeHTTP(listRes, listReq)
	if listRes.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", listRes.Code)
	}
	if !strings.Contains(listRes.Body.String(), "My Home") {
		t.Fatalf("expected created home in response: %s", listRes.Body.String())
	}
}
