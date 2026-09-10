package httpapi

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/application"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/matter"
	"github.com/PoryaNoorzadeh/Manisa-app/internal/storage/sqlite"
)

type fakeMatterController struct {
	commissionResult matter.CommissionResult
	executedNode     matter.NodeID
	executedCommand  matter.Command
	removedNode      matter.NodeID
}

func (f *fakeMatterController) Commission(context.Context, matter.CommissionRequest) (matter.CommissionResult, error) {
	return f.commissionResult, nil
}
func (f *fakeMatterController) RemoveNode(_ context.Context, nodeID matter.NodeID) error { f.removedNode = nodeID; return nil }
func (f *fakeMatterController) Execute(_ context.Context, nodeID matter.NodeID, command matter.Command) error { f.executedNode = nodeID; f.executedCommand = command; return nil }

func newTestRouter(t *testing.T, controller matter.Controller) http.Handler {
	t.Helper()
	db, err := sqlite.Open(t.TempDir() + "/manisa.db")
	if err != nil { t.Fatal(err) }
	t.Cleanup(func() { _ = db.Close() })
	store := sqlite.NewStore(db)
	app := application.New(store, controller)
	return NewRouter(slog.New(slog.NewTextHandler(os.Stdout, nil)), db, app)
}

func TestLiveness(t *testing.T) {
	router := newTestRouter(t, nil)
	req := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	res := httptest.NewRecorder()
	router.ServeHTTP(res, req)
	if res.Code != http.StatusOK { t.Fatalf("expected 200, got %d", res.Code) }
}

func TestCreateAndListHome(t *testing.T) {
	router := newTestRouter(t, nil)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/homes", strings.NewReader(`{"name":"My Home"}`))
	createRes := httptest.NewRecorder()
	router.ServeHTTP(createRes, createReq)
	if createRes.Code != http.StatusCreated { t.Fatalf("expected 201, got %d: %s", createRes.Code, createRes.Body.String()) }
	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/homes", nil)
	listRes := httptest.NewRecorder()
	router.ServeHTTP(listRes, listReq)
	if listRes.Code != http.StatusOK { t.Fatalf("expected 200, got %d", listRes.Code) }
	if !strings.Contains(listRes.Body.String(), "My Home") { t.Fatalf("expected created home in response: %s", listRes.Body.String()) }
}

func TestCommissionAndControlMatterDevice(t *testing.T) {
	controller := &fakeMatterController{commissionResult: matter.CommissionResult{NodeID: "42"}}
	router := newTestRouter(t, controller)
	homeReq := httptest.NewRequest(http.MethodPost, "/api/v1/homes", strings.NewReader(`{"name":"Lab"}`))
	homeRes := httptest.NewRecorder()
	router.ServeHTTP(homeRes, homeReq)
	if homeRes.Code != http.StatusCreated { t.Fatalf("create home: %d %s", homeRes.Code, homeRes.Body.String()) }
	var home struct { ID string `json:"id"` }
	if err := json.NewDecoder(homeRes.Body).Decode(&home); err != nil { t.Fatal(err) }
	commissionBody := `{"homeId":"` + home.ID + `","name":"Test Switch","productType":"switch","transport":"matter_wifi","setupPayload":"MT:TEST","wifiSsid":"ManisaLab","wifiPassword":"secret"}`
	commissionReq := httptest.NewRequest(http.MethodPost, "/api/v1/matter/commission", strings.NewReader(commissionBody))
	commissionRes := httptest.NewRecorder()
	router.ServeHTTP(commissionRes, commissionReq)
	if commissionRes.Code != http.StatusCreated { t.Fatalf("commission: %d %s", commissionRes.Code, commissionRes.Body.String()) }
	var device struct { ID string `json:"id"`; ExternalNodeID *string `json:"externalNodeId"` }
	if err := json.NewDecoder(commissionRes.Body).Decode(&device); err != nil { t.Fatal(err) }
	if device.ExternalNodeID == nil || *device.ExternalNodeID != "42" { t.Fatalf("expected node 42, got %#v", device.ExternalNodeID) }
	commandReq := httptest.NewRequest(http.MethodPost, "/api/v1/devices/"+device.ID+"/commands", strings.NewReader(`{"endpoint":1,"capability":"on_off","action":"on"}`))
	commandRes := httptest.NewRecorder()
	router.ServeHTTP(commandRes, commandReq)
	if commandRes.Code != http.StatusNoContent { t.Fatalf("command: %d %s", commandRes.Code, commandRes.Body.String()) }
	if controller.executedNode != "42" { t.Fatalf("expected command for node 42, got %s", controller.executedNode) }
	if controller.executedCommand.ClusterID != 6 || controller.executedCommand.Name != "on" { t.Fatalf("unexpected command: %#v", controller.executedCommand) }
}
