package server

import (
	"context"
	"time"
)

// RuntimeProvider is the lifecycle boundary between PalPanel and the process
// environment that hosts PalServer. Implementations must verify process
// identity before returning a running state or sending a signal.
type RuntimeProvider interface {
	Mode() string
	Install(context.Context) error
	Update(context.Context) error
	Validate(context.Context) error
	Start(context.Context, []string) error
	Save(context.Context) error
	GracefulShutdown(context.Context) error
	Stop(context.Context) error
	ForceStop(context.Context) error
	Restart(context.Context, []string) error
	Status(context.Context) (RuntimeStatus, error)
	Health(context.Context) (RuntimeHealth, error)
	Metrics(context.Context) (RuntimeMetrics, error)
	Logs(context.Context, int) (string, error)
	PreserveStartArgs(context.Context, []string) error
	RestoreRuntimeState(context.Context) error
}

type RuntimeStatus struct {
	State          string    `json:"state"`
	PID            int       `json:"pid,omitempty"`
	ProcessGroupID int       `json:"process_group_id,omitempty"`
	StartedAt      time.Time `json:"started_at,omitempty"`
	ExitCode       *int      `json:"exit_code,omitempty"`
	StopReason     string    `json:"stop_reason,omitempty"`
}

type RuntimeHealth struct {
	Healthy bool     `json:"healthy"`
	Phase   string   `json:"phase,omitempty"`
	Checks  []string `json:"checks,omitempty"`
}

type RuntimeMetrics struct {
	CPUPercent  float64 `json:"cpu_percent"`
	MemoryBytes uint64  `json:"memory_bytes"`
}
