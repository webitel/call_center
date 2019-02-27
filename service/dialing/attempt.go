package dialing

import "github.com/webitel/call_center/model"

type Attempt struct {
	queue    *Queue
	resource *Resource
	member   *model.MemberAttempt
}

func NewAttempt(queue *Queue, resource *Resource, member *model.MemberAttempt) *Attempt {
	return &Attempt{
		queue:    queue,
		resource: resource,
		member:   member,
	}
}
