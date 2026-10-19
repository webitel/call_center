package rabbit

import (
	"testing"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/webitel/call_center/model"
)

func TestReadMessageSystemSettingEvent(t *testing.T) {
	cases := []struct {
		name string
		rk   string
		want *model.SystemSettingEvent
	}{
		{
			name: "update",
			rk:   "system_settings.record_all_calls.update.7.1",
			want: &model.SystemSettingEvent{Name: model.SysNameRecordAllCalls, DomainID: 7},
		},
		{
			name: "delete",
			rk:   "system_settings.record_all_calls.delete.12.0",
			want: &model.SystemSettingEvent{Name: model.SysNameRecordAllCalls, DomainID: 12},
		},
		{name: "bad domain", rk: "system_settings.record_all_calls.update.x.1"},
		{name: "zero domain", rk: "system_settings.record_all_calls.update.0.1"},
		{name: "too short", rk: "system_settings.record_all_calls"},
		{name: "other object", rk: "users.record_all_calls.update.7.1"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			a := testAMQP()
			a.systemSettingEvent = make(chan model.SystemSettingEvent, 1)

			a.readMessage(&amqp.Delivery{Exchange: model.EventExchange, RoutingKey: tc.rk})

			select {
			case got := <-a.systemSettingEvent:
				if tc.want == nil {
					t.Fatalf("unexpected event %+v", got)
				}

				if got != *tc.want {
					t.Fatalf("got %+v, want %+v", got, *tc.want)
				}
			default:
				if tc.want != nil {
					t.Fatalf("no event, want %+v", *tc.want)
				}
			}
		})
	}
}
