package app

import "github.com/webitel/call_center/cluster"

func (app *App) Cluster() cluster.Cluster {
	return app.cluster
}
