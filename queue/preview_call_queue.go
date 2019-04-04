package queue

type PreviewCallQueue struct {
	CallingQueue
}

func NewPreviewCallQueue(callQueue CallingQueue) QueueObject {
	return &PreviewCallQueue{}
}

func (preview *PreviewCallQueue) FoundAgentForAttempt(attempt *Attempt) {
	panic(`FoundAgentForAttempt queue not reserve agents`)
}

func (preview *PreviewCallQueue) JoinAttempt(attempt *Attempt) {

}

func (preview *PreviewCallQueue) SetHangupCall(attempt *Attempt, event Event) {

}
