package sqlstore

import (
	"fmt"
	"github.com/webitel/wlog"
	"strings"
	"time"
)

type sqlLogger struct {
	minDuration time.Duration
}

func (l *sqlLogger) Printf(format string, v ...interface{}) {
	if len(v) == 4 {
		d, ok := v[3].(time.Duration)
		if ok && d > l.minDuration {
			wlog.Warn(fmt.Sprintf("sql time %v [%s]", d, strings.Replace(fmt.Sprintf("%s", v[1]), "\n", " ", -1)))
		}
	}
}
