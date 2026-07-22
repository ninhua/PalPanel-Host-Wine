package server

import (
	"context"
	"encoding/json"
)

const kvHostWineProcess = "host_wine_process"

// hostWineProcessRecord is persisted so a restarted panel can safely recover
// a PalServer session without trusting a reusable PID by itself.
type hostWineProcessRecord struct {
	PID            int    `json:"pid"`
	ProcessGroupID int    `json:"process_group_id"`
	StartTimeTicks uint64 `json:"start_time_ticks"`
	ShippingPath   string `json:"shipping_path"`
	WinePrefix     string `json:"wine_prefix"`
}

func (m Manager) persistHostWineProcess(ctx context.Context, record hostWineProcessRecord) error {
	raw, err := json.Marshal(record)
	if err != nil {
		return err
	}
	return m.store.SetKV(ctx, kvHostWineProcess, string(raw))
}

func (m Manager) loadHostWineProcess(ctx context.Context) (hostWineProcessRecord, bool, error) {
	raw, ok, err := m.store.GetKV(ctx, kvHostWineProcess)
	if err != nil || !ok || raw == "" {
		return hostWineProcessRecord{}, false, err
	}
	var record hostWineProcessRecord
	if err := json.Unmarshal([]byte(raw), &record); err != nil {
		return hostWineProcessRecord{}, false, err
	}
	return record, true, nil
}

func (m Manager) clearHostWineProcess(ctx context.Context) error {
	return m.store.SetKV(ctx, kvHostWineProcess, "")
}
