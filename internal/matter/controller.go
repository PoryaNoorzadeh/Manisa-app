package matter

import "context"

type NodeID string

type CommissionRequest struct {
	SetupPayload  string
	WiFiSSID      string
	WiFiPassword  string
	ThreadDataset string
	NetworkOnly   bool
}

type CommissionResult struct {
	NodeID NodeID
}

type Command struct {
	Endpoint  uint16
	ClusterID uint32
	Name      string
	Payload   map[string]any
}

type Controller interface {
	Commission(ctx context.Context, req CommissionRequest) (CommissionResult, error)
	RemoveNode(ctx context.Context, nodeID NodeID) error
	Execute(ctx context.Context, nodeID NodeID, command Command) error
}
