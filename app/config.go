package app

import (
	"github.com/BoRuDar/configuration/v4"
	"github.com/webitel/call_center/model"
)

func (a *App) Config() *model.Config {
	if cfg := a.config.Load(); cfg != nil {
		return cfg.(*model.Config)
	}
	return &model.Config{}
}

func (a *App) LoadConfig(string) error {
	if conf, err := loadConfig(); err != nil {
		return err
	} else {
		a.config.Store(conf)
	}
	return nil
}

func loadConfig() (*model.Config, error) {
	var config model.Config
	configurator := configuration.New(
		&config,
		configuration.NewEnvProvider(),
		configuration.NewFlagProvider(),
		configuration.NewDefaultProvider(),
	).SetOptions(configuration.OnFailFnOpt(func(err error) {
		//log.Println(err)
	}))

	if err := configurator.InitValues(); err != nil {
		//return nil, err
	}

	if !config.Log.Console && !config.Log.Otel && len(config.Log.File) == 0 {
		config.Log.Console = true
	}

	return &config, nil
}
