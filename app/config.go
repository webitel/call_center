package app

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
)

func (a *App) Config() *model.Config {
	if cfg := a.config.Load(); cfg != nil {
		return cfg.(*model.Config)
	}
	return &model.Config{}
}

func (a *App) LoadConfig(configFile string) *model.AppError {
	cfg, configPath, _, err := utils.LoadConfig(configFile)
	if err != nil {
		return err
	}

	a.configFile = configPath

	a.config.Store(cfg)
	return nil
}
