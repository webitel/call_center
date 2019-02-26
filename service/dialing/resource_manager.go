package dialing

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
	"sync"
)

const (
	SIZE_RESOURCES_CACHE = 10000
	EXPIRE_CACHE_ITEM    = 60 * 60 * 24 //day
)

type ResourceManager struct {
	cache utils.ObjectCache
	app   App
	sync.Mutex
}

func NewResourceManager(app App) *ResourceManager {
	return &ResourceManager{
		cache: utils.NewLruWithParams(SIZE_RESOURCES_CACHE, "ResourceManager", EXPIRE_CACHE_ITEM, ""),
		app:   app,
	}
}

func (r *ResourceManager) Get(id int64, updatedAt int64) (*Resource, *model.AppError) {
	r.Lock()
	defer r.Unlock()
	var dialResource *Resource
	item, ok := r.cache.Get(id)
	if ok {
		dialResource, ok = item.(*Resource)
		if ok && !dialResource.IsExpire(updatedAt) {
			return dialResource, nil
		}
	}

	if config, err := r.app.GetOutboundResourceById(id); err != nil {
		return nil, err
	} else {
		dialResource = NewResource(config)
	}

	r.cache.AddWithDefaultExpires(id, dialResource)
	mlog.Debug(fmt.Sprintf("Add resource %s to cache", dialResource.Name()))
	return dialResource, nil
}
