package utils

import (
	"context"
	"golang.org/x/time/rate"
	"time"
)

type RateLimiter struct {
	rate uint16
	*rate.Limiter
}

func NewRateLimiter(perSec uint16) *RateLimiter {
	rt := rate.Every(time.Second / time.Duration(perSec))
	return &RateLimiter{
		rate:    perSec,
		Limiter: rate.NewLimiter(rt, 1),
	}
}

func (limiter *RateLimiter) Take() {
	limiter.Wait(context.TODO())
}
