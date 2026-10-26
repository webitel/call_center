package im

import (
	"context"
	"testing"

	"google.golang.org/grpc/metadata"
)

func TestQueueContext(t *testing.T) {
	s := &Session{hdrs: metadata.New(map[string]string{"x-webitel-type": "schema"})}

	md, _ := metadata.FromOutgoingContext(s.queueContext(context.Background(), Queue{Id: 7, Name: "Черга"}))
	if got := md.Get(queueIDHeader); len(got) != 1 || got[0] != "7" {
		t.Fatalf("queue id header = %v", got)
	}
	if got := md.Get(queueNameHeader); len(got) != 1 || got[0] != "Черга" {
		t.Fatalf("queue name header = %v", got)
	}
	if got := md.Get("x-webitel-type"); len(got) != 1 || got[0] != "schema" {
		t.Fatalf("session headers lost: %v", got)
	}
	if len(s.hdrs.Get(queueIDHeader)) != 0 {
		t.Fatal("session headers mutated")
	}

	md, _ = metadata.FromOutgoingContext(s.queueContext(context.Background(), Queue{}))
	if len(md.Get(queueIDHeader)) != 0 || len(md.Get(queueNameHeader)) != 0 {
		t.Fatalf("queue headers sent without queue: %v", md)
	}
}
