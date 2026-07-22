//go:build !linux

package server

import (
	"context"
	"fmt"

	"palpanel/internal/docker"
)

func (m Manager) startHostWine(context.Context, []string) error {
	return fmt.Errorf("host_wine runtime requires Linux host")
}

func (m Manager) stopHostWine(context.Context) error {
	return fmt.Errorf("host_wine runtime requires Linux host")
}

func (m Manager) hostWineStatus(context.Context) (docker.ContainerStatus, error) {
	return docker.ContainerStatus{Status: "error"}, fmt.Errorf("host_wine runtime requires Linux host")
}
