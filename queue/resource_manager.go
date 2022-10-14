package queue

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"golang.org/x/sync/singleflight"
	"net/http"
	"sync"
)

const (
	SIZE_RESOURCES_CACHE = 10000
	EXPIRE_CACHE_ITEM    = 60 * 60 * 24 //day
)

var (
	resourceGroupRequest singleflight.Group
)

type ResourceManager struct {
	resourcesCache utils.ObjectCache
	patternsCache  utils.ObjectCache
	app            App
	sync.Mutex
}

func NewResourceManager(app App) *ResourceManager {
	return &ResourceManager{
		resourcesCache: utils.NewLruWithParams(SIZE_RESOURCES_CACHE, "ResourceManager", EXPIRE_CACHE_ITEM, ""),
		patternsCache:  utils.NewLruWithParams(SIZE_RESOURCES_CACHE, "ResourcePatternCache", -1, ""),
		app:            app,
	}
}

func (r *ResourceManager) Get(id int64, updatedAt int64) (ResourceObject, *model.AppError) {
	var dialResource ResourceObject
	item, ok := r.resourcesCache.Get(id)
	if ok {
		dialResource, ok = item.(ResourceObject)
		if ok && !dialResource.IsExpire(updatedAt) {
			return dialResource, nil
		}
	}

	result, err, shared := resourceGroupRequest.Do(fmt.Sprintf("res-%d-%d", id, updatedAt), func() (interface{}, error) {
		if config, err := r.app.GetOutboundResourceById(id); err != nil {
			return nil, err
		} else {
			if gw, err := r.app.GetGateway(config.GatewayId); err != nil {
				return nil, err
			} else {
				resource, _ := NewResource(config, *gw)
				return resource, nil
			}
		}
	})

	if err != nil {
		switch err.(type) {
		case *model.AppError:
			return nil, err.(*model.AppError)
		default:
			return nil, model.NewAppError("Queue", "queue.manager.resource.get", nil, err.Error(), http.StatusInternalServerError)
		}
	}

	dialResource = result.(ResourceObject)

	if !shared {
		r.resourcesCache.AddWithDefaultExpires(id, dialResource)
		wlog.Debug(fmt.Sprintf("add resource %s to cache", dialResource.Name()))
	}

	return dialResource, nil
}

func (r *ResourceManager) RemoveFromCacheById(id int64) {
	r.resourcesCache.Remove(id)
}
