package sqlstore

import (
	"github.com/go-gorp/gorp"
	"github.com/webitel/call_center/model"
	"reflect"
)

type PostgresJSONDialect struct {
	gorp.PostgresDialect
}

func (d PostgresJSONDialect) ToSqlType(val reflect.Type, maxsize int, isAutoIncr bool) string {
	if val == reflect.TypeOf(model.StringInterface{}) {
		return "JSONB"
	}
	return d.PostgresDialect.ToSqlType(val, maxsize, isAutoIncr)
}
