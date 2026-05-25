package audit

import (
	"context"
	"time"
)

type Event struct {
	At        time.Time
	ActorID   int64
	Action    string
	Subject   string
	IPAddress string
	Metadata  map[string]any
}

type Recorder interface {
	Record(ctx context.Context, event Event) error
}
