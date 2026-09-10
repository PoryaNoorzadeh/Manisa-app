package matter

import "context"

type AttributeEvent struct {
	NodeID  NodeID
	Path    string
	Value   any
	Initial bool
}

type EventSource interface {
	Listen(ctx context.Context, handler func(context.Context, AttributeEvent) error) error
}
