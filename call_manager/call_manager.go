package call_manager

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/external_commands"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/engine/discovery"
	"github.com/webitel/wlog"
	"net/http"
	"sync"
)

const (
	MAX_CALL_CACHE        = 50000
	MAX_CALL_EXPIRE_CACHE = 60 * 60 * 24 //day

	WATCHER_INTERVAL = 1000 * 5 // 30s
)

type CallManager interface {
	Start()
	Stop()
	ActiveCalls() int
	NewCall(callRequest *model.CallRequest) (Call, *model.AppError)
	GetCall(id string) (Call, bool)
	InboundCallQueue(call *model.Call, ringtone string, vars map[string]string) (Call, *model.AppError)
	ConnectCall(call *model.Call, ringtone string) (Call, *model.AppError)
	CountConnection() int
	GetFlowUri() string
	RingtoneUri(domainId int64, id int, mimeType string) string
	HangupManyCall(cause string, ids ...string)
	HangupById(id, node string) *model.AppError
}

type CallManagerImpl struct {
	nodeId string

	serviceDiscovery discovery.ServiceDiscovery
	poolConnections  discovery.Pool

	flowSocketUri string

	mq        mq.MQ
	calls     utils.ObjectCache
	stop      chan struct{}
	stopped   chan struct{}
	watcher   *utils.Watcher
	proxy     string
	cdr       string
	startOnce sync.Once
}

func NewCallManager(nodeId string, serviceDiscovery discovery.ServiceDiscovery, mq mq.MQ) CallManager {
	return &CallManagerImpl{
		nodeId:           nodeId,
		poolConnections:  discovery.NewPoolConnections(),
		serviceDiscovery: serviceDiscovery,
		mq:               mq,
		stop:             make(chan struct{}),
		stopped:          make(chan struct{}),
		calls:            utils.NewLruWithParams(MAX_CALL_CACHE, "CallManager", MAX_CALL_EXPIRE_CACHE, ""),
	}
}

func (cm *CallManagerImpl) Start() {
	wlog.Debug("starting call manager service")

	if services, err := cm.serviceDiscovery.GetByName(model.CLUSTER_CALL_SERVICE_NAME); err != nil {
		panic(err) //TODO
	} else {
		for _, v := range services {
			cm.registerConnection(v)
		}
	}

	cm.startOnce.Do(func() {
		cm.watcher = utils.MakeWatcher("CallManager", WATCHER_INTERVAL, cm.wakeUp)
		go cm.watcher.Start()
		go func() {
			defer func() {
				wlog.Debug("stopped CallManager")
				close(cm.stopped)
			}()

			for {
				select {
				case <-cm.stop:
					wlog.Debug("callManager received stop signal")
					return
				case e, ok := <-cm.mq.ConsumeCallEvent():
					if !ok {
						return
					}
					cm.handleCallAction(e)
				}
			}
		}()
	})
}

func (cm *CallManagerImpl) Stop() {
	wlog.Debug("callManager Stopping")

	if cm.watcher != nil {
		cm.watcher.Stop()
	}

	if cm.poolConnections != nil {
		cm.poolConnections.CloseAllConnections()
	}

	close(cm.stop)
	<-cm.stopped
}

func DUMP(i interface{}) string {
	s, _ := json.MarshalIndent(i, "", "\t")
	wlog.Error(string(s))
	return string(s)
}

func (cm *CallManagerImpl) NewCall(callRequest *model.CallRequest) (Call, *model.AppError) {
	api, err := cm.getApiConnection()
	if err != nil {
		return nil, err
	}
	return NewCall(CALL_DIRECTION_OUTBOUND, callRequest, cm, api), nil
}

func (cm *CallManagerImpl) HangupManyCall(cause string, ids ...string) {
	var ok bool
	var call interface{}

	for _, id := range ids {
		if call, ok = cm.calls.Get(id); ok {
			call.(Call).Hangup(cause, false, nil)
		}
	}
}

func (cm *CallManagerImpl) HangupById(id, node string) *model.AppError {
	cli, err := cm.getApiConnectionById(node)

	if err != nil {
		return err
	}

	return cli.HangupCall(id, model.CALL_HANGUP_LOSE_RACE, false, nil)
}

func (cm *CallManagerImpl) InboundCallQueue(call *model.Call, ringtone string, vars map[string]string) (Call, *model.AppError) {
	cli, err := cm.getApiConnectionById(call.AppId)
	if err != nil {
		return nil, err
	}

	err = cli.JoinQueue(context.Background(), call.Id, ringtone, model.UnionStringMaps(vars, map[string]string{
		model.QUEUE_NODE_ID_FIELD: cm.nodeId,
		"cc_result":               "abandoned",
	}))

	if err != nil {
		return nil, err
	}

	if c, ok := cm.calls.Get(call.Id); ok {
		cc := c.(Call)
		if cc.Direction() == CALL_DIRECTION_OUTBOUND {
			err = cc.UpdateCid()
		}
		cc.ResetBridge()
		wlog.Debug(fmt.Sprintf("call %s is queue", call.Id))
		return cc, err
	}

	res := &CallImpl{
		callRequest: nil,
		id:          call.Id,
		api:         cli,
		cm:          cm,
		hangupCh:    make(chan struct{}),
		chState:     make(chan CallState, 5),
		acceptAt:    call.AnsweredAt,
		ringingAt:   call.CreatedAt,
		state:       CALL_STATE_ACCEPT, //FIXME
	}

	if call.Direction == model.CALL_DIRECTION_OUTBOUND {
		res.direction = model.CALL_DIRECTION_OUTBOUND
	} else {
		res.direction = model.CALL_DIRECTION_INBOUND
	}

	res.info = model.CallActionInfo{
		GatewayId:   nil,
		UserId:      nil,
		Direction:   call.Direction,
		Destination: call.Destination,
		From: &model.CallEndpoint{
			Type:   "dest",
			Id:     call.FromNumber,
			Number: call.FromNumber,
			Name:   call.FromName,
		},
		To:       nil,
		ParentId: nil,
		Payload:  nil,
	}

	cm.saveToCacheCall(res)

	wlog.Debug(fmt.Sprintf("[%s] call %s init request", res.NodeName(), res.Id()))

	return res, nil
}

func (cm *CallManagerImpl) ConnectCall(call *model.Call, ringtone string) (Call, *model.AppError) {
	var err *model.AppError
	var cli model.CallCommands

	if c, ok := cm.calls.Get(call.Id); ok {
		cc := c.(Call)
		if cc.Direction() == CALL_DIRECTION_OUTBOUND {
			err = cc.UpdateCid()
		}
		cc.ResetBridge()
		wlog.Debug(fmt.Sprintf("call %s is queue", call.Id))
		return cc, err
	}

	cli, err = cm.getApiConnectionById(call.AppId)
	if err != nil {
		return nil, err
	}

	err = cli.JoinQueue(context.Background(), call.Id, ringtone, map[string]string{
		model.QUEUE_NODE_ID_FIELD: cm.nodeId,
		"cc_result":               "abandoned",
	})

	if err != nil {
		return nil, err
	}

	res := &CallImpl{
		callRequest: nil,
		id:          call.Id,
		api:         cli,
		cm:          cm,
		hangupCh:    make(chan struct{}),
		chState:     make(chan CallState, 5),
		acceptAt:    call.AnsweredAt,
		ringingAt:   call.CreatedAt,
		state:       CALL_STATE_ACCEPT, //FIXME
	}

	if call.Direction == model.CALL_DIRECTION_OUTBOUND {
		res.direction = model.CALL_DIRECTION_OUTBOUND
	} else {
		res.direction = model.CALL_DIRECTION_INBOUND
	}

	res.info = model.CallActionInfo{
		GatewayId:   nil,
		UserId:      nil,
		Direction:   call.Direction,
		Destination: call.Destination,
		From: &model.CallEndpoint{
			Type:   "dest",
			Id:     call.FromNumber,
			Number: call.FromNumber,
			Name:   call.FromName,
		},
		To:       nil,
		ParentId: nil,
		Payload:  nil,
	}

	//todo
	cli.SetCallVariables(call.Id, map[string]string{
		model.QUEUE_NODE_ID_FIELD: cm.nodeId,
		"cc_result":               "abandoned",
	})

	cm.saveToCacheCall(res)

	wlog.Debug(fmt.Sprintf("[%s] call %s init request", res.NodeName(), res.Id()))

	return res, nil
}

func (cm *CallManagerImpl) ActiveCalls() int {
	return cm.calls.Len()
}

func (cm *CallManagerImpl) GetCall(id string) (Call, bool) {
	if call, ok := cm.calls.Get(id); ok {
		return call.(Call), true
	}
	return nil, false
}

func (cm *CallManagerImpl) GetFlowUri() string {
	return "socket " + cm.flowSocketUri
}

func (cm *CallManagerImpl) RingtoneUri(domainId int64, id int, mimeType string) string {
	switch mimeType {
	case "audio/mp3", "audio/mpeg":
		return fmt.Sprintf("shout://%s/sys/media/%d/stream?domain_id=%d&.mp3", cm.cdr, id, domainId)
	case "audio/wav":
		return fmt.Sprintf("http_cache://http://%s/sys/media/%d/stream?domain_id=%d&.wav", cm.cdr, id, domainId)
	default:
		return ""
	}
}

func (cm *CallManagerImpl) registerConnection(v *discovery.ServiceConnection) {
	var version, cdr string
	var sps int
	client, err := external_commands.NewCallConnection(v.Id, fmt.Sprintf("%s:%d", v.Host, v.Port))
	if err != nil {
		wlog.Error(fmt.Sprintf("connection %s error: %s", v.Id, err.Error()))
		return
	}

	if version, err = client.GetServerVersion(); err != nil {
		wlog.Error(fmt.Sprintf("connection %s get version error: %s", v.Id, err.Error()))
		return
	}

	if sps, err = client.GetRemoteSps(); err != nil {
		wlog.Error(fmt.Sprintf("connection %s get SPS error: %s", v.Id, err.Error()))
		return
	}

	if cdr, err = client.GetCdrUri(); err != nil {
		wlog.Error(fmt.Sprintf("connection %s get CDR error: %s", v.Id, err.Error()))
		return
	}

	if cm.cdr == "" {
		cm.cdr = cdr
	}

	client.SetConnectionSps(sps)

	//FIXME add connection proxy value
	cm.proxy, err = client.GetParameter("outbound_sip_proxy")
	if err != nil {
		wlog.Error(fmt.Sprintf("connection %s get proxy error: %s", v.Id, err.Error()))
		return
	}

	if cm.flowSocketUri == "" {
		if cm.flowSocketUri, err = client.GetSocketUri(); err != nil {
			wlog.Error(fmt.Sprintf("connection %s get flow uri error: %s", v.Id, err.Error()))
			return
		}
	}

	cm.poolConnections.Append(client)
	wlog.Debug(fmt.Sprintf("register connection %s [%s] [sps=%d]", client.Name(), version, sps))
}

func (cm *CallManagerImpl) getApiConnection() (model.CallCommands, *model.AppError) {
	conn, err := cm.poolConnections.Get(discovery.StrategyRoundRobin)
	if err != nil {
		return nil, model.NewAppError("CallManager", "call_manager.get_client.app_error", nil, err.Error(), http.StatusInternalServerError)
	}
	return conn.(model.CallCommands), nil
}

func (cm *CallManagerImpl) getApiConnectionById(id string) (model.CallCommands, *model.AppError) {
	conn, err := cm.poolConnections.GetById(id)
	if err != nil {
		return nil, model.NewAppError("CallManager", "call_manager.get_client.app_error", nil, err.Error(), http.StatusInternalServerError)
	}
	return conn.(model.CallCommands), nil
}

func (cm *CallManagerImpl) wakeUp() {
	list, err := cm.serviceDiscovery.GetByName(model.CLUSTER_CALL_SERVICE_NAME)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	for _, v := range list {
		if _, err := cm.poolConnections.GetById(v.Id); err == discovery.ErrNotFoundConnection {
			cm.registerConnection(v)
		}
	}
	cm.poolConnections.RecheckConnections(list.Ids())
}

func (cm *CallManagerImpl) saveToCacheCall(call Call) {
	wlog.Debug(fmt.Sprintf("[%s] call %s save to store", call.NodeName(), call.Id()))
	cm.calls.AddWithDefaultExpires(call.Id(), call)
}

func (cm *CallManagerImpl) removeFromCacheCall(call Call) {
	wlog.Debug(fmt.Sprintf("[%s] call %s remove from store", call.NodeName(), call.Id()))
	cm.calls.Remove(call.Id())
}

func (cm *CallManagerImpl) CountConnection() int {
	return len(cm.poolConnections.All())
}
