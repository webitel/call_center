package utils

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"go.uber.org/atomic"
	"sync"
)

//https://github.com/uber-go/ratelimit
//https://github.com/golang/go/wiki/RateLimiting
type RateLimiter struct {
	rate    int
	nextGet atomic.Int64
	sync.Mutex
}

func NewRateLimiter(perSec int) *RateLimiter {
	return &RateLimiter{
		rate: perSec,
	}
}

func (limiter *RateLimiter) Throttle() bool {
	limiter.Lock()
	defer limiter.Unlock()
	fmt.Println(limiter.nextGet.Load(), model.GetMillis())
	if limiter.nextGet.Load() < model.GetMillis() {
		limiter.nextGet.Store((model.GetMillis() + (int64(limiter.rate) * 1000)))
		return true
	}

	return false
}
