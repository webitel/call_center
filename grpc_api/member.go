package grpc_api

import (
	"context"
	"errors"
	"fmt"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/queue"
	"github.com/webitel/protos/cc"
)

type member struct {
	app *app.App
	cc.UnsafeMemberServiceServer
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
		Status:        in.GetStatus(),
		Description:   in.GetDescription(),
		Display:       in.GetDisplay(),
		Variables:     in.Variables,
		StickyAgentId: nil,
		NextCallAt:    nil,
		ExpireAt:      nil,
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

	err := api.app.Queue().Manager().ReportingAttempt(in.AttemptId, result, false)
	if err != nil {
		return nil, err
	}
	return &cc.AttemptResultResponse{
		Status: "success", //TODO
	}, nil
}

func (api *member) CallJoinToQueue(in *cc.CallJoinToQueueRequest, out cc.MemberService_CallJoinToQueueServer) error {

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

func (api *member) ChatJoinToQueue(in *cc.ChatJoinToQueueRequest, out cc.MemberService_ChatJoinToQueueServer) error {
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

func (api *member) CallJoinToAgent(in *cc.CallJoinToAgentRequest, out cc.MemberService_CallJoinToAgentServer) error {
	ctx := context.Background()
	attempt, err := api.app.Queue().Manager().DistributeCallToAgent(ctx, in)
	if err != nil {
		return err
	}

	bridged := attempt.On(queue.AttemptHookBridgedAgent)
	leaving := attempt.On(queue.AttemptHookLeaving)

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

func (api *member) ProcessingFormAction(_ context.Context, in *cc.ProcessingFormActionRequest) (*cc.ProcessingFormActionResponse, error) {

	err := api.app.Queue().Manager().AttemptProcessingActionForm(in.AttemptId, in.Action, in.Fields)
	if err != nil {
		return nil, err
	}

	return &cc.ProcessingFormActionResponse{}, nil
}
