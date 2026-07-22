//go:build !linux

package server

import "context"

func (m Manager) preflightHostWineSaveGames(context.Context) error {
	return nil
}
