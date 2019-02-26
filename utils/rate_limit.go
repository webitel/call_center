package utils

//https://github.com/golang/go/wiki/RateLimiting
type RateLimiter struct {
	rate    int
	lastGet int64
}
