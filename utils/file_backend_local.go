package utils

import (
	"github.com/webitel/call_center/model"
	"io"
	"net/http"
	"os"
	"path/filepath"
)

type LocalFileBackend struct {
	pathPattern string
	rootPath    string
	name        string
}

func (self *LocalFileBackend) GetLocation(name string) string {
	return ""
}

func (self *LocalFileBackend) TestConnection() *model.AppError {
	return nil
}

func (self *LocalFileBackend) WriteFile(src io.Reader, path string) (int64, *model.AppError) {
	if err := os.MkdirAll(filepath.Dir(path), 0774); err != nil {
		directory, _ := filepath.Abs(filepath.Dir(path))
		return 0, model.NewAppError("WriteFile", "utils.file.locally.create_dir.app_error", nil, "directory="+directory+", err="+err.Error(), http.StatusInternalServerError)
	}
	fw, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return 0, model.NewAppError("WriteFile", "utils.file.locally.writing.app_error", nil, err.Error(), http.StatusInternalServerError)
	}
	defer fw.Close()
	written, err := io.Copy(fw, src)
	if err != nil {
		return written, model.NewAppError("WriteFile", "utils.file.locally.writing.app_error", nil, err.Error(), http.StatusInternalServerError)
	}
	return written, nil
}

func (self *LocalFileBackend) RemoveFile(path string) *model.AppError {
	if err := os.Remove(path); err != nil {
		return model.NewAppError("RemoveFile", "utils.file.locally.removing.app_error", nil, err.Error(), http.StatusInternalServerError)
	}
	return nil
}
