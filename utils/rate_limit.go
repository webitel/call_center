package utils

import (
	"sync"
	"time"
)

//https://github.com/uber-go/ratelimit
//https://github.com/golang/go/wiki/RateLimiting
type RateLimiter struct {
	rate    time.Duration
	lastGet int64
	sync.Mutex
}

func NewRateLimiter(perSec int) *RateLimiter {
	return &RateLimiter{
		rate: (time.Second / time.Duration(perSec)),
	}
}

func (limiter *RateLimiter) Throttle() {
	limiter.Lock()
	defer limiter.Unlock()

}
