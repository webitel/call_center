package grpc

import (
	"google.golang.org/grpc"
	"log"

	"github.com/webitel/call_center/grpc/fs"
	"context"
	"time"
	"fmt"
)

func NewClient()  {
	return
	var opts []grpc.DialOption
	opts = append(opts, grpc.WithInsecure())
	conn, err := grpc.Dial("10.10.10.25:50051", opts...)
	if err != nil {
		log.Fatalf("fail to dial: %v", err)
	}

	defer conn.Close()
	client := fs.NewApiClient(conn)

	var i = 0
	for {
		i++
		go send(client, i)
		time.Sleep(time.Millisecond * 1)
		if i > 0 {
			break
		}
	}

	time.Sleep(time.Minute);
}

func send(client fs.ApiClient, i int)  {
	res, err := client.Originate(context.Background(), &fs.OriginateRequest{
		Endpoints: []string{"user/1003@10.10.10.25"},
		Destination: "dialer-00",
		Variables: map[string]string{
			"var": "val",
		},
		Timeout: 40,
		CallerName: "Igor",
		CallerNumber: "380973080466",
		Dialplan: "XML",
		Context: "public",
	})
	if err != nil {
		log.Fatalf("%v.GetFeatures(_) = _, %v: ", client, err)
	}

	if res.Uuid != ""  {

		client.Hangup(context.Background(), &fs.HangupRequest{
			Uuid: res.Uuid,
			Cause: "USER_BUSY",
		})
	}
	if res.Error == nil {
		fmt.Println("OKOKOK")
	}
	fmt.Println(res)
}