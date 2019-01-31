package utils

import (
	"github.com/webitel/call_center/model"
	"io"
	"net/http"
)

type FileBackend interface {
	TestConnection() *model.AppError
	WriteFile(fr io.Reader, path string) (int64, *model.AppError)
	RemoveFile(path string) *model.AppError
	GetLocation(name string) string
}

func NewFileBackend(backendType string) (FileBackend, *model.AppError) {
	return nil, model.NewAppError("NewFileBackend", "api.file.no_driver.app_error", nil, "",
		http.StatusInternalServerError)
}
