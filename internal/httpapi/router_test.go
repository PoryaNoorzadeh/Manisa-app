package httpapi

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/storage/sqlite"
)

func TestLiveness(t *testing.T) {
	db, err := sqlite.Open(t.TempDir() + "/manisa.db")
	if err != nil { t.Fatal(err) }
	defer db.Close()

	router := NewRouter(slog.New(slog.NewTextHandler(os.Stdout, nil)), db)
	req := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	res := httptest.NewRecorder()
	router.ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.Code)
	}
}
