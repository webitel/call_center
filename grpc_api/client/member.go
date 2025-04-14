package client

import (
	gogrpc "buf.build/gen/go/webitel/cc/grpc/go/_gogrpc"
	proto "buf.build/gen/go/webitel/cc/protocolbuffers/go"
	"context"
)

type memberApi struct {
	cli *ccManager
}

func NewMemberApi(m *ccManager) MemberApi {
	return &memberApi{
		cli: m,
	}
}

func (api *memberApi) JoinCallToQueue(ctx context.Context, in *proto.CallJoinToQueueRequest) (gogrpc.MemberService_CallJoinToQueueClient, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return nil, err
	}

	return cli.member.CallJoinToQueue(ctx, in)
}

func (api *memberApi) JoinChatToQueue(ctx context.Context, in *proto.ChatJoinToQueueRequest) (gogrpc.MemberService_ChatJoinToQueueClient, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return nil, err
	}

	return cli.member.ChatJoinToQueue(ctx, in)
}

func (api *memberApi) DirectAgentToMember(domainId int64, memberId int64, communicationId int, agentId int64) (int64, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return 0, err
	}
	res, err := cli.member.DirectAgentToMember(context.Background(), &proto.DirectAgentToMemberRequest{
		MemberId:        memberId,
		AgentId:         agentId,
		DomainId:        domainId,
		CommunicationId: int32(communicationId),
	})

	if err != nil {
		return 0, err
	}

	return res.AttemptId, nil
}

func (api *memberApi) AttemptResult(result *proto.AttemptResultRequest) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.member.AttemptResult(context.Background(), result)

	if err != nil {
		return err
	}

	return nil
}

func (api *memberApi) RenewalResult(domainId, attemptId int64, renewal uint32) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.member.AttemptRenewalResult(context.Background(), &proto.AttemptRenewalResultRequest{
		DomainId:  domainId,
		AttemptId: attemptId,
		Renewal:   renewal,
	})

	return err
}

func (api *memberApi) CallJoinToAgent(ctx context.Context, in *proto.CallJoinToAgentRequest) (gogrpc.MemberService_CallJoinToAgentClient, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return nil, err
	}

	return cli.member.CallJoinToAgent(ctx, in)
}

func (api *memberApi) TaskJoinToAgent(ctx context.Context, in *proto.TaskJoinToAgentRequest) (gogrpc.MemberService_TaskJoinToAgentClient, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return nil, err
	}

	return cli.member.TaskJoinToAgent(ctx, in)
}

func (api *memberApi) CancelAgentDistribute(ctx context.Context, in *proto.CancelAgentDistributeRequest) (*proto.CancelAgentDistributeResponse, error) {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return nil, err
	}

	return cli.member.CancelAgentDistribute(ctx, in)
}

func (api *memberApi) ProcessingActionForm(ctx context.Context, in *proto.ProcessingFormActionRequest) (*proto.ProcessingFormActionResponse, error) {

	cli, err := api.cli.getClient(in.AppId)
	if err != nil {
		return nil, err
	}

	return cli.member.ProcessingFormAction(ctx, in)
}

func (api *memberApi) ProcessingActionComponent(ctx context.Context, in *proto.ProcessingComponentActionRequest) (*proto.ProcessingComponentActionResponse, error) {

	cli, err := api.cli.getClient(in.AppId)
	if err != nil {
		return nil, err
	}

	return cli.member.ProcessingComponentAction(ctx, in)
}

func (api *memberApi) CancelAttempt(ctx context.Context, attemptId int64, result, appId string) error {
	cli, err := api.cli.getClient(appId)
	if err != nil {
		return err
	}

	_, err = cli.member.CancelAttempt(ctx, &proto.CancelAttemptRequest{
		AttemptId: attemptId,
		Result:    result,
	})

	return err
}

func (api *memberApi) InterceptAttempt(ctx context.Context, domainId int64, attemptId int64, agentId int32) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.member.InterceptAttempt(ctx, &proto.InterceptAttemptRequest{
		DomainId:  domainId,
		AttemptId: attemptId,
		AgentId:   agentId,
	})

	return err
}

func (api *memberApi) ResumeAttempt(ctx context.Context, attemptId int64, domainId int64) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.member.ResumeAttempt(ctx, &proto.ResumeAttemptRequest{
		DomainId:  domainId,
		AttemptId: attemptId,
	})

	return err
}

func (api *memberApi) SaveFormFields(domainId, attemptId int64, fields map[string]string, form []byte) error {
	cli, err := api.cli.getRandomClient()
	if err != nil {
		return err
	}

	_, err = cli.member.ProcessingFormSave(context.Background(), &proto.ProcessingFormSaveRequest{
		DomainId:  domainId,
		AttemptId: attemptId,
		Fields:    fields,
		Form:      form,
	})

	return err
}
