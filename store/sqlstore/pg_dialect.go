package sqlstore

import (
	"database/sql"
	"github.com/go-gorp/gorp"
	"github.com/lib/pq"
	"github.com/webitel/call_center/model"
	"net/http"
	"reflect"
)

type PostgresJSONDialect struct {
	gorp.PostgresDialect
}

const ForeignKeyViolationErrorCode = pq.ErrorCode("23503")
const DuplicationViolationErrorCode = pq.ErrorCode("23505")

func (d PostgresJSONDialect) ToSqlType(val reflect.Type, maxsize int, isAutoIncr bool) string {
	if val == reflect.TypeOf(model.StringInterface{}) {
		return "JSONB"
	}
	return d.PostgresDialect.ToSqlType(val, maxsize, isAutoIncr)
}

func extractCodeFromErr(err error) int {
	code := http.StatusInternalServerError

	if err == sql.ErrNoRows {
		code = http.StatusNotFound
	} else if e, ok := err.(*pq.Error); ok {
		switch e.Code {
		case ForeignKeyViolationErrorCode, DuplicationViolationErrorCode:
			code = http.StatusBadRequest
		}
	}
	return code
}
