package model

const (
	DEFAULT_LOCALE = "en"

	DATABASE_DRIVER_POSTGRES = "postgres"
)

type LocalizationSettings struct {
	DefaultServerLocale *string
	DefaultClientLocale *string
	AvailableLocales    *string
}

func (s *LocalizationSettings) SetDefaults() {
	if s.DefaultServerLocale == nil {
		s.DefaultServerLocale = NewString(DEFAULT_LOCALE)
	}

	if s.DefaultClientLocale == nil {
		s.DefaultClientLocale = NewString(DEFAULT_LOCALE)
	}

	if s.AvailableLocales == nil {
		s.AvailableLocales = NewString("")
	}
}

type ServiceSettings struct {
	NodeId *string
	//ListenAddress         *string
	//ListenInternalAddress *string
}

type CallSettings struct {
	UseBridgeAnswerTimeout   bool
	ResourceSipCidType       string `json:"sip_cid_type"`
	ResourceIgnoreEarlyMedia string `json:"ignore_early_media"`
}

type SqlSettings struct {
	DriverName                  *string
	DataSource                  *string
	DataSourceReplicas          []string
	DataSourceSearchReplicas    []string
	MaxIdleConns                *int
	ConnMaxLifetimeMilliseconds *int
	MaxOpenConns                *int
	Trace                       bool
	AtRestEncryptKey            string
	QueryTimeout                *int
}

type MessageQueueSettings struct {
	Url string
}

type ServerSettings struct {
	Address string `json:"address"`
	Port    int    `json:"port"`
	Network string `json:"network"`
}

type ExternalCommandsConnection struct {
	Name string
	Url  string
}

type DiscoverySettings struct {
	Url string
}

type Config struct {
	DiscoverySettings    DiscoverySettings `json:"discovery_settings"`
	LocalizationSettings LocalizationSettings
	ServiceSettings      ServiceSettings
	ServerSettings       ServerSettings
	SqlSettings          SqlSettings
	MessageQueueSettings MessageQueueSettings
	CallSettings         CallSettings
}
