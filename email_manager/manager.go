package email_manager

type Email struct {
}

func (e *Email) Reply(message []byte) {

}

type EmailManager interface {
	InboundEmail()
}

type manager struct {
}

func New() EmailManager {
	return &manager{}
}

func (m *manager) InboundEmail() {

}

func (m *manager) Reply() {

}
