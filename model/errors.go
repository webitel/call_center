package model

import "net/http"

var (
	ErrQueueMaxWaitSize = NewAppError("Queue", "queue.bad_request.max_wait_size", nil, "Queue max wait size", http.StatusBadRequest)
)
