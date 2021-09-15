package app

import "github.com/webitel/call_center/model"

func (a *App) GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError) {
	r, err := a.Store.OutboundResource().GetById(id)
	if err != nil {
		return nil, err
	}
	conf := a.Config().CallSettings

	if r.Parameters.IgnoreEarlyMedia == "" && conf.ResourceIgnoreEarlyMedia != "" {
		r.Parameters.IgnoreEarlyMedia = conf.ResourceIgnoreEarlyMedia
	}

	if r.Parameters.SipCidType == "" && conf.ResourceSipCidType != "" {
		r.Parameters.SipCidType = conf.ResourceSipCidType
	}

	return r, nil
}

func (a *App) GetGateway(id int64) (*model.SipGateway, *model.AppError) {
	gw, err := a.Store.Gateway().Get(id)
	if err != nil {
		return nil, err
	}

	gw.UseBridgeAnswerTimeout = a.Config().CallSettings.UseBridgeAnswerTimeout

	return gw, nil
}
