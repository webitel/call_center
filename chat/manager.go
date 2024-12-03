package chat

import (
	"github.com/webitel/call_center/mq"
	"github.com/webitel/engine/chat_manager"
	"github.com/webitel/engine/discovery"
	"github.com/webitel/engine/utils"
	"github.com/webitel/wlog"
	"sync"
)

const (
	maxOpenedChat   = 50000
	expireCacheChat = 0 //30 * 60 * 60 * 24 //day
)

type ChatManager struct {
	stop      chan struct{}
	stopped   chan struct{}
	startOnce sync.Once
	mq        mq.MQ
	chats     utils.ObjectCache
	api       chat_manager.ChatManager
	log       *wlog.Logger
}

func NewChatManager(discovery discovery.ServiceDiscovery, mq mq.MQ, log *wlog.Logger) *ChatManager {
	return &ChatManager{
		stop:    make(chan struct{}),
		stopped: make(chan struct{}),
		api:     chat_manager.NewChatManager(discovery),
		mq:      mq,
		chats:   utils.NewLruWithParams(maxOpenedChat, "Chats", expireCacheChat, ""),
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "chat manager"),
		),
	}
}

func (m *ChatManager) Start() error {
	m.startOnce.Do(func() {
		go func() {
			defer func() {
				m.log.Debug("stopped chat")
				close(m.stopped)
			}()

			for {
				select {
				case <-m.stop:
					m.log.Debug("chat received stop signal")
					return
				case e, ok := <-m.mq.ConsumeChatEvent():
					if !ok {
						return
					}

					m.handleEvent(&e)
				}
			}
		}()
	})

	return m.api.Start()
}

func (m *ChatManager) Stop() {
	m.api.Stop()
	close(m.stop)
	<-m.stopped
}
