package chat

//func (cm *ChatManager) Outbound(domainId, userId int64, conversationId, inviterId, invUserId string) (*ChatSession, *model.AppError) {
//	cli, err := cm.api.Client()
//	if err != nil {
//		return nil, model.NewAppError("Chat.Outbound", "chat.outbound.app_err", nil, err.Error(), http.StatusInternalServerError)
//	}
//
//	sess := OutboundChat(cli, domainId, userId, conversationId, inviterId, invUserId)
//	cm.StoreChat(sess)
//
//	return sess, nil
//}
//
//func (cm *ChatManager) Inbound(domainId int64, conversationId, inviterId, invUserId string) (*ChatSession, *model.AppError) {
//	cli, err := cm.api.Client()
//	if err != nil {
//		return nil, model.NewAppError("Chat.Inbound", "chat.inbound.app_err", nil, err.Error(), http.StatusInternalServerError)
//	}
//
//	sess := InboundChat(cli, domainId, conversationId, inviterId, invUserId)
//	cm.StoreChat(sess)
//
//	return sess, nil
//}
