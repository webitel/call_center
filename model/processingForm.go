package model

import "context"

type ProcessingForm interface {
	Id() string
	Form() []byte
	ActionForm(ctx context.Context, action string, vars map[string]string) ([]byte, error)
	Close() error
	Fields() map[string]string
}
