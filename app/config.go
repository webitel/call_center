package app

import (
	"crypto/tls"
	"crypto/x509"
	"os"

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
		// log.Println(err)
	}))

	if err := configurator.InitValues(); err != nil {
		// return nil, err
	}

	if !config.Log.Console && !config.Log.Otel && len(config.Log.File) == 0 {
		config.Log.Console = true
	}

	return &config, nil
}

func LoadTlsCreds(cfg model.TLSConfig) (*tls.Config, error) {
	if len(cfg.CertPath) == 0 || len(cfg.KeyPath) == 0 || len(cfg.CAPath) == 0 {
		return nil, nil
	}

	// Load client's certificate and private key
	clientCert, err := tls.LoadX509KeyPair(cfg.CertPath, cfg.KeyPath)
	if err != nil {
		return nil, err
	}

	// Load the CA certificate to verify server
	caCert, err := os.ReadFile(cfg.CAPath)
	if err != nil {
		return nil, err
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	// Configure TLS
	return &tls.Config{
		Certificates: []tls.Certificate{clientCert},
		RootCAs:      caCertPool,
		ServerName:   "im-gateway-service", // Common Name of the server cert
	}, nil
}
