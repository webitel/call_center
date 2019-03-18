package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"net/http"
	"regexp"
)

type Endpoint struct {
	rg *regexp.Regexp
}

func NewResourceEndpoint(pattern string) (*Endpoint, *model.AppError) {
	rg, err := regexp.Compile(pattern)
	if err != nil {
		return nil, model.NewAppError("ResourceManager.GetEndpoint", "resource_manager.ger_endpoint.regexp.app_error", nil,
			fmt.Sprintf("Bad RegExp %s", err.Error()), http.StatusInternalServerError)
	}
	return &Endpoint{rg}, nil
}

func (endpoint *Endpoint) Parse(src, destination string) string {
	return endpoint.rg.ReplaceAllString(destination, src)
}
