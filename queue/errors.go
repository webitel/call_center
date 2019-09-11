package queue

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func NewErrorResourceRequired(queue QueueObject, attempt *Attempt) *model.AppError {
	return model.NewAppError(
		"Queue",
		"queue.distribute.invalid_resource.error",
		map[string]interface{}{"QueueId": queue.Id(), "AttemptId": attempt.Id()},
		"",
		http.StatusUnauthorized,
	)
}

func NewErrorAgentRequired(queue QueueObject, attempt *Attempt) *model.AppError {
	return model.NewAppError(
		"Queue",
		"queue.distribute.invalid_agent.error",
		map[string]interface{}{"QueueId": queue.Id(), "AttemptId": attempt.Id()},
		"",
		http.StatusUnauthorized,
	)
}

func NewErrorCommunicationPatternRequired(queue QueueObject, attempt *Attempt) *model.AppError {
	return model.NewAppError(
		"Queue",
		"queue.distribute.invalid_communication_pattern.error",
		map[string]interface{}{"QueueId": queue.Id(), "AttemptId": attempt.Id()},
		"",
		http.StatusUnauthorized,
	)
}
