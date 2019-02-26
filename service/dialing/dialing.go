package dialing

import (
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/utils"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 400

type DialingImpl struct {
	app       App
	watcher   *utils.Watcher
	resource  *ResourceManager
	startOnce sync.Once
}

func NewDialing(app App) Dialing {
	var dialing DialingImpl
	dialing.app = app
	dialing.resource = NewResourceManager(app)
	return &dialing
}

func (dialing *DialingImpl) Start() {
	mlog.Debug("Starting dialing service")
	dialing.watcher = utils.MakeWatcher("Dialing", DEFAULT_WATCHER_POLLING_INTERVAL, dialing.PollAndNotify)

	dialing.startOnce.Do(func() {
		go dialing.watcher.Start()
	})
}

func (d *DialingImpl) Stop() {
	d.watcher.Stop()
}

func (d *DialingImpl) MakeCalls() {

}

func (d *DialingImpl) PollAndNotify() {

}
