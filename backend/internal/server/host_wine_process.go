package server

// hostWineProcessRecord is persisted so a restarted panel can safely recover
// a PalServer session without trusting a reusable PID by itself.
type hostWineProcessRecord struct {
	PID            int    `json:"pid"`
	ProcessGroupID int    `json:"process_group_id"`
	StartTimeTicks uint64 `json:"start_time_ticks"`
	ShippingPath   string `json:"shipping_path"`
	WinePrefix     string `json:"wine_prefix"`
}
