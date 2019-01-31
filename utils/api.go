package utils

import (
	"github.com/webitel/call_center/model"
	"net/http"
	"strings"
)

func CheckOrigin(r *http.Request, allowedOrigins string) bool {
	origin := r.Header.Get("Origin")
	if allowedOrigins == "*" {
		return true
	}
	for _, allowed := range strings.Split(allowedOrigins, " ") {
		if allowed == origin {
			return true
		}
	}
	return false
}

func OriginChecker(allowedOrigins string) func(*http.Request) bool {
	return func(r *http.Request) bool {
		return CheckOrigin(r, allowedOrigins)
	}
}

func RenderWebAppError(config *model.Config, w http.ResponseWriter, r *http.Request, err *model.AppError) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(err.StatusCode)
	w.Write([]byte(err.ToJson()))
}
