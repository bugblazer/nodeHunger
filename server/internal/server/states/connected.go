package states

import (
	"fmt"
	"log"
	"server/internal/server"
	"server/pkg/packets"
)

// A struct for the state
type Connected struct {
	client server.ClientInterfacer
	logger *log.Logger
}

// Functions for methods that were initialized in the
// ClientStateHandler interface in hub.go
func (c *Connected) Name() string {
	return "Connected"
}

func (c *Connected) SetClient(client server.ClientInterfacer) {
	c.client = client
	loggingPrefix := fmt.Sprintf("Client %d [%s]: ", client.Id(), c.Name())
	c.logger = log.New(log.Writer(), loggingPrefix, log.LstdFlags)
}

func (c *Connected) OnEnter() {
	c.client.SocketSend(packets.NewId(c.client.Id()))
}

func (c *Connected) HandleMessage(senderId uint64, message packets.Msg) {
	if senderId == c.client.Id() {
		//means the message was sent from our own client, so just broadcast it to others
		c.client.Broadcast(message)
	} else {
		//Another client sent it or got it from the hub, then forward to client
		c.client.SocketSendAs(message, senderId)
	}
}

func (c *Connected) OnExit() {

}
