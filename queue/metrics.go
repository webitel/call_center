package queue

import (
	"context"
	"strconv"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"

	"github.com/webitel/call_center/model"
)

const pacingMeterName = "call_center/predictive"

type pacingMetrics struct {
	overDial      metric.Float64Gauge
	abandonRate   metric.Float64Gauge
	targetAbandon metric.Float64Gauge
	maxPredict    metric.Int64Gauge
	loseRaceTotal metric.Int64Counter
}

var globalPacingMetrics *pacingMetrics

func initPacingMetrics() {
	m := otel.GetMeterProvider().Meter(pacingMeterName)

	overDial, _ := m.Float64Gauge("cc_predictive_over_dial",
		metric.WithDescription("Current AIMD over_dial multiplier per queue/bucket"))
	abandonRate, _ := m.Float64Gauge("cc_predictive_abandoned_rate",
		metric.WithDescription("EWMA abandoned rate (%) per queue/bucket"))
	targetAbandon, _ := m.Float64Gauge("cc_predictive_target_abandon",
		metric.WithDescription("Target abandoned rate (%) per queue/bucket"))
	maxPredict, _ := m.Int64Gauge("cc_predictive_max_predict",
		metric.WithDescription("Maximum concurrent outbound calls per iteration per queue/bucket"))
	loseRaceTotal, _ := m.Int64Counter("cc_predictive_lose_race_total",
		metric.WithDescription("Total agent race losses in predictive distribution"))

	globalPacingMetrics = &pacingMetrics{
		overDial:      overDial,
		abandonRate:   abandonRate,
		targetAbandon: targetAbandon,
		maxPredict:    maxPredict,
		loseRaceTotal: loseRaceTotal,
	}
}

func recordPacingStats(ctx context.Context, rows []*model.PacingStatRow) {
	if globalPacingMetrics == nil {
		return
	}
	for _, r := range rows {
		bucket := "none"
		if r.BucketID != nil {
			bucket = strconv.Itoa(int(*r.BucketID))
		}
		attrs := metric.WithAttributes(
			attribute.String("queue", strconv.FormatInt(r.QueueID, 10)),
			attribute.String("bucket", bucket),
		)
		globalPacingMetrics.overDial.Record(ctx, r.OverDial, attrs)
		globalPacingMetrics.abandonRate.Record(ctx, r.AbandonRate, attrs)
		globalPacingMetrics.targetAbandon.Record(ctx, r.TargetAbandon, attrs)
		globalPacingMetrics.maxPredict.Record(ctx, int64(r.MaxPredict), attrs)
	}
}

func recordLoseRace(ctx context.Context, queueID int64, agentID int) {
	if globalPacingMetrics == nil {
		return
	}
	globalPacingMetrics.loseRaceTotal.Add(ctx, 1,
		metric.WithAttributes(
			attribute.String("queue", strconv.FormatInt(queueID, 10)),
			attribute.String("agent", strconv.Itoa(agentID)),
		),
	)
}
