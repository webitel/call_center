package grpc_api

import (
	grpc "buf.build/gen/go/webitel/cc/grpc/go/_gogrpc"
	cc "buf.build/gen/go/webitel/cc/protocolbuffers/go"
	"context"
	"errors"
	"fmt"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/queue"
)

type member struct {
	app *app.App
	grpc.UnsafeMemberServiceServer
}

func NewMemberApi(a *app.App) *member {
	return &member{app: a}
}

func (api *member) CancelAgentDistribute(_ context.Context, in *cc.CancelAgentDistributeRequest) (*cc.CancelAgentDistributeResponse, error) {
	err := api.app.Queue().Manager().CancelAgentDistribute(in.AgentId)
	if err != nil {
		return nil, err
	}

	return &cc.CancelAgentDistributeResponse{}, nil
}

func terminateMember(status string) bool {
	switch status {
	case "success", "terminate", "cancel":
		return true
	}

	return false
}

func (api *member) CancelAttempt(ctx context.Context, in *cc.CancelAttemptRequest) (*cc.CancelAttemptResponse, error) {
	ok := api.app.Queue().Manager().SetAttemptCancel(in.AttemptId, in.Result)
	if !ok {
		return nil, errors.New("not found")
	}

	return &cc.CancelAttemptResponse{}, nil
}

func (api *member) AttemptResult(_ context.Context, in *cc.AttemptResultRequest) (*cc.AttemptResultResponse, error) {
	result := model.AttemptCallback{
		Status:                   in.GetStatus(),
		Description:              in.GetDescription(),
		Display:                  in.GetDisplay(),
		Variables:                in.Variables,
		StickyAgentId:            nil,
		NextCallAt:               nil,
		ExpireAt:                 nil,
		OnlyCurrentCommunication: nil,
	}

	if in.ExpireAt > 0 {
		result.ExpireAt = model.Int64ToTime(in.GetExpireAt())
	}

	if in.NextDistributeAt > 0 && !terminateMember(result.Status) {
		result.NextCallAt = model.Int64ToTime(in.NextDistributeAt)
	}

	if in.AgentId > 0 {
		result.StickyAgentId = model.NewInt(int(in.AgentId))
	}

	if in.ExcludeCurrentCommunication {
		result.ExcludeCurrentCommunication = model.NewBool(true)
	}

	if in.Redial {
		result.Redial = model.NewBool(true)
	}

	if in.WaitBetweenRetries > 0 {
		result.WaitBetweenRetries = &in.WaitBetweenRetries
	}

	if in.OnlyCurrentCommunication {
		result.OnlyCurrentCommunication = &in.OnlyCurrentCommunication
	}

	l := len(in.AddCommunications)
	if l != 0 {
		result.AddCommunications = make([]model.MemberCommunication, 0, l)
		for _, v := range in.AddCommunications {
			c := model.MemberCommunication{
				Destination: v.Destination,
				Type: model.Communication{
					Id: int(v.GetType().GetId()),
				},
				Priority:    int(v.Priority),
				Description: v.Description,
			}

			if v.Display != "" {
				c.Display = &v.Display
			}
			result.AddCommunications = append(result.AddCommunications, c)
		}
	}

	err := api.app.Queue().Manager().ReportingAttempt(in.AttemptId, result, false)
	if err != nil {
		return nil, err
	}
	return &cc.AttemptResultResponse{
		Status: "success", //TODO
	}, nil
}

func (api *member) CallJoinToQueue(in *cc.CallJoinToQueueRequest, out grpc.MemberService_CallJoinToQueueServer) error {

	ctx := out.Context()
	attempt, err := api.app.Queue().Manager().DistributeCall(ctx, in)
	if err != nil {
		if err == model.ErrQueueMaxWaitSize {
			out.Send(&cc.QueueEvent{
				Data: &cc.QueueEvent_Leaving{
					Leaving: &cc.QueueEvent_LeavingData{
						Result: queue.AttemptResultMaxWaitSize,
					},
				},
			})
			return nil
		}
		return err
	}

	bridged := attempt.On(queue.AttemptHookBridgedAgent)
	leaving := attempt.On(queue.AttemptHookLeaving)
	offering := attempt.On(queue.AttemptHookOfferingAgent)

	e := out.Send(&cc.QueueEvent{
		Data: &cc.QueueEvent_Joined{
			Joined: &cc.QueueEvent_JoinedData{
				AttemptId: attempt.Id(),
				AppId:     api.app.GetInstanceId(),
			},
		},
	})
	if e != nil {
		return e
	}

	for {
		select {
		case <-leaving:
			out.Send(&cc.QueueEvent{
				Data: &cc.QueueEvent_Leaving{
					Leaving: &cc.QueueEvent_LeavingData{
						Result: attempt.Result(),
					},
				},
			})
			goto stop
		case id, ok := <-offering:
			a := attempt.Agent()
			if a != nil && ok && len(id.Args) > 0 {
				out.Send(&cc.QueueEvent{
					Data: &cc.QueueEvent_Offering{
						Offering: &cc.QueueEvent_OfferingData{
							AgentId:     int32(a.Id()),
							AgentCallId: fmt.Sprintf("%s", id.Args[0]),
							AgentName:   a.Name(),
						},
					},
				})
			}
		case _, ok := <-bridged:
			if ok {
				out.Send(&cc.QueueEvent{
					Data: &cc.QueueEvent_Bridged{
						Bridged: &cc.QueueEvent_BridgedData{
							AgentId: 0, //TODO
						},
					},
				})
			}
		}
	}

stop:

	return nil
}

func (api *member) ChatJoinToQueue(in *cc.ChatJoinToQueueRequest, out grpc.MemberService_ChatJoinToQueueServer) error {
	ctx := out.Context()
	attempt, err := api.app.Queue().Manager().DistributeChatToQueue(ctx, in)
	if err != nil {
		if err == model.ErrQueueMaxWaitSize {
			out.Send(&cc.QueueEvent{
				Data: &cc.QueueEvent_Leaving{
					Leaving: &cc.QueueEvent_LeavingData{
						Result: queue.AttemptResultMaxWaitSize,
					},
				},
			})
			return nil
		}
		return err
	}

	bridged := attempt.On(queue.AttemptHookBridgedAgent)
	leaving := attempt.On(queue.AttemptHookLeaving)
	offering := attempt.On(queue.AttemptHookOfferingAgent)
	missed := attempt.On(queue.AttemptHookMissedAgent)

	e := out.Send(&cc.QueueEvent{
		Data: &cc.QueueEvent_Joined{
			Joined: &cc.QueueEvent_JoinedData{
				AttemptId: attempt.Id(),
				AppId:     api.app.GetInstanceId(),
			},
		},
	})
	if e != nil {
		return e
	}

	for {
		select {
		case <-out.Context().Done():
			attempt.Log("cancel context")
			attempt.SetCancel()
			goto stop
			//attempt.memberChannel.Id()
		case <-leaving:
			out.Send(&cc.QueueEvent{
				Data: &cc.QueueEvent_Leaving{
					Leaving: &cc.QueueEvent_LeavingData{
						Result: attempt.Result(),
					},
				},
			})
			goto stop

		case _, ok := <-offering:
			if ok {
				a := attempt.Agent()
				out.Send(&cc.QueueEvent{
					Data: &cc.QueueEvent_Offering{
						Offering: &cc.QueueEvent_OfferingData{
							AgentId:   int32(a.Id()),
							AgentName: a.Name(),
						},
					},
				})
			}

		case _, ok := <-missed:
			if ok {
				out.Send(&cc.QueueEvent{
					Data: &cc.QueueEvent_Missed{
						Missed: &cc.QueueEvent_MissedAgent{
							Timeout: 0,
						},
					},
				})
			}

		case _, ok := <-bridged:
			if ok {
				out.Send(&cc.QueueEvent{
					Data: &cc.QueueEvent_Bridged{
						Bridged: &cc.QueueEvent_BridgedData{
							AgentId: 0, //TODO
						},
					},
				})
			}
		}
	}

stop:

	return nil
}

func (api *member) DirectAgentToMember(_ context.Context, in *cc.DirectAgentToMemberRequest) (*cc.DirectAgentToMemberResponse, error) {
	res, err := api.app.Queue().Manager().DistributeDirectMember(in.GetMemberId(), int(in.GetCommunicationId()), int(in.GetAgentId()))
	if err != nil {
		return nil, err
	}

	return &cc.DirectAgentToMemberResponse{
		AttemptId: res.Id(),
	}, nil
}

func (api *member) EmailJoinToQueue(_ context.Context, in *cc.EmailJoinToQueueRequest) (*cc.EmailJoinToQueueResponse, error) {
	return nil, nil
}

func (api *member) AttemptRenewalResult(_ context.Context, in *cc.AttemptRenewalResultRequest) (*cc.AttemptRenewalResultResponse, error) {
	err := api.app.Queue().Manager().RenewalAttempt(in.DomainId, in.AttemptId, in.Renewal)
	if err != nil {
		return nil, err
	}

	return &cc.AttemptRenewalResultResponse{}, nil
}

func (api *member) CallJoinToAgent(in *cc.CallJoinToAgentRequest, out grpc.MemberService_CallJoinToAgentServer) error {
	ctx := context.Background()
	attempt, err := api.app.Queue().Manager().DistributeCallToAgent(ctx, in)
	if err != nil {
		return err
	}

	bridged := attempt.On(queue.AttemptHookBridgedAgent)
	leaving := attempt.On(queue.AttemptHookLeaving)

	out.Send(&cc.QueueEvent{
		Data: &cc.QueueEvent_Joined{
			Joined: &cc.QueueEvent_JoinedData{
				AttemptId: attempt.Id(),
				AppId:     "",
			},
		},
	})

	for {
		select {
		case <-leaving:
			out.Send(&cc.QueueEvent{
				Data: &cc.QueueEvent_Leaving{
					Leaving: &cc.QueueEvent_LeavingData{
						Result: attempt.Result(),
					},
				},
			})
			goto stop
		case _, ok := <-bridged:
			if ok {
				br := &cc.QueueEvent_BridgedData{
					AgentId: 0,
				}

				if attempt.AgentId() != nil {
					br.AgentId = int32(*attempt.AgentId())
				}
				out.Send(&cc.QueueEvent{
					Data: &cc.QueueEvent_Bridged{
						Bridged: br,
					},
				})
			}
		}
	}

stop:

	return nil
}

func (api *member) TaskJoinToAgent(in *cc.TaskJoinToAgentRequest, out grpc.MemberService_TaskJoinToAgentServer) error {
	ctx := context.Background()
	attempt, err := api.app.Queue().Manager().DistributeTaskToAgent(ctx, in)
	if err != nil {
		return err
	}

	bridged := attempt.On(queue.AttemptHookBridgedAgent)
	leaving := attempt.On(queue.AttemptHookLeaving)

	out.Send(&cc.QueueEvent{
		Data: &cc.QueueEvent_Joined{
			Joined: &cc.QueueEvent_JoinedData{
				AttemptId: attempt.Id(),
				AppId:     "",
			},
		},
	})

	for {
		select {
		case <-leaving:
			out.Send(&cc.QueueEvent{
				Data: &cc.QueueEvent_Leaving{
					Leaving: &cc.QueueEvent_LeavingData{
						Result: attempt.Result(),
					},
				},
			})
			goto stop
		case _, ok := <-bridged:
			if ok {
				br := &cc.QueueEvent_BridgedData{
					AgentId: 0,
				}

				if attempt.AgentId() != nil {
					br.AgentId = int32(*attempt.AgentId())
				}
				out.Send(&cc.QueueEvent{
					Data: &cc.QueueEvent_Bridged{
						Bridged: br,
					},
				})
			}
		}
	}

stop:

	return nil
}

func (api *member) ProcessingFormAction(_ context.Context, in *cc.ProcessingFormActionRequest) (*cc.ProcessingFormActionResponse, error) {

	err := api.app.Queue().Manager().AttemptProcessingActionForm(in.AttemptId, in.Action, in.Fields)
	if err != nil {
		return nil, err
	}

	return &cc.ProcessingFormActionResponse{}, nil
}

func (api *member) InterceptAttempt(ctx context.Context, in *cc.InterceptAttemptRequest) (*cc.InterceptAttemptResponse, error) {
	err := api.app.Queue().Manager().InterceptAttempt(ctx, in.DomainId, in.AttemptId, in.AgentId)
	if err != nil {
		return nil, err
	}

	return &cc.InterceptAttemptResponse{}, nil
}

func (api *member) ResumeAttempt(ctx context.Context, in *cc.ResumeAttemptRequest) (*cc.ResumeAttemptResponse, error) {
	err := api.app.Queue().Manager().ResumeAttempt(in.AttemptId, in.DomainId)
	if err != nil {
		return nil, err
	}

	return &cc.ResumeAttemptResponse{
		Ok: true,
	}, nil
}

func (api *member) OutboundCall(*cc.OutboundCallReqeust, grpc.MemberService_OutboundCallServer) error {
	return errors.New("TODO")
}

func (api *member) ProcessingFormSave(ctx context.Context, in *cc.ProcessingFormSaveRequest) (*cc.ProcessingFormSaveResponse, error) {
	err := api.app.Queue().Manager().SaveFormFields(ctx, in.DomainId, in.AttemptId, in.Fields, in.Form)
	if err != nil {
		return nil, err
	}

	return &cc.ProcessingFormSaveResponse{}, nil
}

func (api *member) Transfer(context.Context, *cc.TransferRequest) (*cc.TransferResponse, error) {
	return nil, errors.New("TODO")
}
