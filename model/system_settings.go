package model

import (
	"fmt"
	"strconv"
	"strings"
)

const (
	SystemSettingsObjectName = "system_settings"
	SysNameRecordAllCalls    = "record_all_calls"
)

type SystemSettingEvent struct {
	Name     string
	DomainID int64
}

func NewSystemSettingEventFromRoutingKey(rk string) (SystemSettingEvent, error) {
	parts := strings.Split(rk, ".")
	if len(parts) < 4 || parts[0] != SystemSettingsObjectName || parts[1] == "" {
		return SystemSettingEvent{}, fmt.Errorf("unexpected system settings routing key %q", rk)
	}

	domainID, err := strconv.ParseInt(parts[3], 10, 64)
	if err != nil || domainID <= 0 {
		return SystemSettingEvent{}, fmt.Errorf("invalid domain id in system settings routing key %q", rk)
	}

	return SystemSettingEvent{Name: parts[1], DomainID: domainID}, nil
}
