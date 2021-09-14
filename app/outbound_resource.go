package app

import "github.com/webitel/call_center/model"

func (a *App) GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError) {
	return a.Store.OutboundResource().GetById(id)
}

func (a *App) GetGateway(id int64) (*model.SipGateway, *model.AppError) {
	gw, err := a.Store.Gateway().Get(id)
	if err != nil {
		return nil, err
	}

	conf := a.Config()

	gw.UseBridgeAnswerTimeout = conf.CallSettings.UseBridgeAnswerTimeout
	gw.SipCidType = conf.CallSettings.ResourceSipCidType
	gw.IgnoreEarlyMedia = conf.CallSettings.ResourceIgnoreEarlyMedia

	return gw, nil
}
