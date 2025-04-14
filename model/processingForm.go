package model

import "context"

type ProcessingForm interface {
	Id() string
	Form() []byte
	ActionForm(ctx context.Context, action string, vars map[string]string) ([]byte, error)
	ActionComponent(ctx context.Context, formId, component string, action string, vars map[string]string) error
	Close() error
	Fields() map[string]string
	Update(f []byte, fields map[string]string) error
}
