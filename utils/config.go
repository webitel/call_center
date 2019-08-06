package utils

import (
	"github.com/webitel/call_center/model"
	"os"
	"path/filepath"
)

var (
	commonBaseSearchPaths = []string{
		".",
		"..",
		"../..",
		"../../..",
	}
)

func LoadConfig(fileName string) (*model.Config, string, map[string]interface{}, *model.AppError) {
	var envConfig = make(map[string]interface{})
	//dbDatasource := "postgres://opensips:webitel@192.168.177.194:5432/webitel?fallback_application_name=call_center&sslmode=disable&connect_timeout=10"
	dbDatasource := "postgres://webitel:webitel@localhost:5432/webitel?fallback_application_name=call_center&sslmode=disable&connect_timeout=10&search_path=call_center"
	dbDriverName := "postgres"
	maxIdleConns := 5
	maxOpenConns := 5
	connMaxLifetimeMilliseconds := 3600000
	sessionCacheInMinutes := 1

	return &model.Config{
		LocalizationSettings: model.LocalizationSettings{
			DefaultClientLocale: model.NewString(model.DEFAULT_LOCALE),
			DefaultServerLocale: model.NewString(model.DEFAULT_LOCALE),
			AvailableLocales:    model.NewString(model.DEFAULT_LOCALE),
		},
		ServiceSettings: model.ServiceSettings{
			NodeId:                model.NewString("call-center-1"),
			ListenAddress:         model.NewString(":10023"),
			SessionCacheInMinutes: &sessionCacheInMinutes,
		},
		SqlSettings: model.SqlSettings{
			DriverName:                  &dbDriverName,
			DataSource:                  &dbDatasource,
			MaxIdleConns:                &maxIdleConns,
			MaxOpenConns:                &maxOpenConns,
			ConnMaxLifetimeMilliseconds: &connMaxLifetimeMilliseconds,
			Trace:                       false,
		},
		MQSettings: model.MQSettings{
			//Url: model.NewString("amqp://webitel:webitel@192.168.177.199:5672?heartbeat=0"), //http://192.168.177.189:15672/
			Url: model.NewString("amqp://webitel:webitel@10.10.10.200:5672?heartbeat=10"), //http://192.168.177.189:15672/
		},
		ExternalCommandsSettings: model.ExternalCommandsSettings{
			Connections: []*model.ExternalCommandsConnection{
				{
					Name: "fs1",
					Url:  "192.168.177.10:50051",
				},
			},

			//"192.168.177.184:50051", "192.168.177.185:50051"
		},
	}, "", envConfig, nil
}

func FindPath(path string, baseSearchPaths []string, filter func(os.FileInfo) bool) string {
	if filepath.IsAbs(path) {
		if _, err := os.Stat(path); err == nil {
			return path
		}

		return ""
	}

	searchPaths := []string{}
	for _, baseSearchPath := range baseSearchPaths {
		searchPaths = append(searchPaths, baseSearchPath)
	}

	// Additionally attempt to search relative to the location of the running binary.
	var binaryDir string
	if exe, err := os.Executable(); err == nil {
		if exe, err = filepath.EvalSymlinks(exe); err == nil {
			if exe, err = filepath.Abs(exe); err == nil {
				binaryDir = filepath.Dir(exe)
			}
		}
	}
	if binaryDir != "" {
		for _, baseSearchPath := range baseSearchPaths {
			searchPaths = append(
				searchPaths,
				filepath.Join(binaryDir, baseSearchPath),
			)
		}
	}

	for _, parent := range searchPaths {
		found, err := filepath.Abs(filepath.Join(parent, path))
		if err != nil {
			continue
		} else if fileInfo, err := os.Stat(found); err == nil {
			if filter != nil {
				if filter(fileInfo) {
					return found
				}
			} else {
				return found
			}
		}
	}

	return ""
}

// FindDir looks for the given directory in nearby ancestors relative to the current working
// directory as well as the directory of the executable, falling back to `./` if not found.
func FindDir(dir string) (string, bool) {
	found := FindPath(dir, commonBaseSearchPaths, func(fileInfo os.FileInfo) bool {
		return fileInfo.IsDir()
	})
	if found == "" {
		return "./", false
	}

	return found, true
}
