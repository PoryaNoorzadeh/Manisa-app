package application

import (
	"sync"
	"sync/atomic"
	"time"

	"github.com/PoryaNoorzadeh/Manisa-app/internal/domain"
)

type eventBus struct {
	mu          sync.RWMutex
	subscribers map[uint64]chan domain.RealtimeEvent
	nextSubID   atomic.Uint64
	sequence    atomic.Uint64
}

func newEventBus() *eventBus {
	return &eventBus{subscribers: make(map[uint64]chan domain.RealtimeEvent)}
}

func (b *eventBus) publish(event domain.RealtimeEvent) {
	event.Sequence = b.sequence.Add(1)
	if event.Timestamp.IsZero() {
		event.Timestamp = time.Now().UTC()
	}

	b.mu.RLock()
	defer b.mu.RUnlock()
	for _, subscriber := range b.subscribers {
		select {
		case subscriber <- event:
		default:
			// State is persisted and can be re-fetched; keep the realtime path
			// non-blocking when a client is too slow.
			select {
			case <-subscriber:
			default:
			}
			select {
			case subscriber <- event:
			default:
			}
		}
	}
}

func (b *eventBus) subscribe(buffer int) (<-chan domain.RealtimeEvent, func()) {
	if buffer < 1 {
		buffer = 1
	}
	id := b.nextSubID.Add(1)
	channel := make(chan domain.RealtimeEvent, buffer)

	b.mu.Lock()
	b.subscribers[id] = channel
	b.mu.Unlock()

	unsubscribe := func() {
		b.mu.Lock()
		delete(b.subscribers, id)
		b.mu.Unlock()
	}
	return channel, unsubscribe
}
