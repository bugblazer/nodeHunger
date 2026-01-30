package clients

import (
	"fmt"
	"log"
	"net/http"

	"server/internal/server"
	"server/pkg/packets"

	"github.com/gorilla/websocket"
	"google.golang.org/protobuf/proto"
)

// Implementation of the websocket client
type WebSocketClient struct {
	id       uint64
	conn     *websocket.Conn
	hub      *server.Hub
	sendChan chan *packets.Packet
	logger   *log.Logger
}

// Creating a constructor for the websocket client
// hub is the first function argument, writer is the second argument
// third argument is the http request
// signature of this constructor matches the signature of handler we wrote in h.serve method in hub.go
// Defining the upgrader to upgrade from http server to a websocket
func NewWebSocketClient(hub *server.Hub, writer http.ResponseWriter, request *http.Request) (server.ClientInterfacer, error) {
	upgrader := websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin:     func(_ *http.Request) bool { return true },
	}

	conn, err := upgrader.Upgrade(writer, request, nil)

	if err != nil {
		return nil, err
	}

	//else
	c := &WebSocketClient{
		hub:  hub,
		conn: conn,
		//Making this channel a buffered one to keep it from clogging if messages are on await
		//allowing it 256 packets before it starts clogging
		sendChan: make(chan *packets.Packet, 256),
		//Making a custom logger that writes the log with "Client unknown" as the prefix since we don't
		//have the client id yet, then it prints the standard flags such as date and time
		logger: log.New(log.Writer(), "Client unknown: ", log.LstdFlags),
	}

	return c, nil
}

// Methods for the WebSocketClient
// retuns the client ID
func (c *WebSocketClient) Id() uint64 {
	return c.id
}

// Intializes the client id and then changes the unknown part of "Client unknown" of the log with client ID
func (c *WebSocketClient) Initialize(id uint64) {
	c.id = id
	c.logger.SetPrefix(fmt.Sprintf("Client %d: ", c.id))
}

// I'll figure out later how to process the message
func (c *WebSocketClient) ProcessMessage(senderId uint64, message packets.Msg) {
	c.logger.Printf("Recieved message from: %T from client. Echoing it back...", message)
	c.SocketSend(message)
}

// Instead of repeating the logic, simply calling the SendSocketAs function here and will write the logic there
func (c *WebSocketClient) SocketSend(message packets.Msg) {
	c.SocketSendAs(message, c.id)
}

func (c *WebSocketClient) SocketSendAs(message packets.Msg, senderId uint64) {
	select {
	//If there's anything to send, sort out the senderId and message, send it to the packet struct
	//Send that to the send channel
	case c.sendChan <- &packets.Packet{SenderId: senderId, Msg: message}:
	//but if the send channel is full(already has 256 packets waiting), drop the message:
	default:
		c.logger.Printf("Send channel full, dropping message: %T", message) //%T will print message type
	}
}

// Checks if the peer is registered and then if it is, sends the message to peer
func (c *WebSocketClient) PassToPeer(message packets.Msg, peerId uint64) {
	if peer, exists := c.hub.Clients.Get(peerId); exists {
		peer.ProcessMessage(c.id, message)
	}
}

// Sends the packet to the broadcast channel, which broadcasts to all connected clients
func (c *WebSocketClient) Broadcast(message packets.Msg) {
	c.hub.BroadcastChan <- &packets.Packet{SenderId: c.id, Msg: message}
}

// Interfacing with the websocket function, reading messages from that websocket and process them
// to turn raw data into protobuf packets
func (c *WebSocketClient) ReadPump() {
	//Make sure that cleanup happens when the ReadPump stops
	defer func() {
		c.logger.Println("Closing read pump")
		c.Close("Read pump closed")
	}()

	//infinite loop to read data
	for {
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			//Checks if error is something expected: (if so, it just logs the error)
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				c.logger.Printf("Error: %v", err)
			}
			break //break after logging the error (goes back to defer to cleanup)
		}

		//else (if there's no error, meaning we have some acceptable data)
		//create an empty packet
		packet := &packets.Packet{}
		err = proto.Unmarshal(data, packet)
		//^Unmarshal (deserialize the data in that empty packet)
		//Now checking for errors while unmarshaling:
		if err != nil {
			c.logger.Printf("Error unmarshaling data: %v", err)
			continue //log the error and go to read the next message
		}

		//Since I'm lazy, allowing the client to not send sender id, gonna assume the client wants to send
		//as itself (This will help in godot though)
		if packet.SenderId == 0 {
			packet.SenderId = c.id
		}

		//Finally sending the packet to the client for processing
		c.ProcessMessage(packet.SenderId, packet.Msg)
	}
}

// This time, we're listening for packets instead of reading them
func (c *WebSocketClient) WritePump() {
	defer func() {
		c.logger.Println("Closing the write pump")
		c.Close("Write pump closed")
	}()

	for packet := range c.sendChan {
		//Getting a binary writer because we're working with binary in protobuf:
		writer, err := c.conn.NextWriter(websocket.BinaryMessage)

		if err != nil {
			c.logger.Printf("Error getting values for %T packet, closing client: %v", packet.Msg, err)
			return //simply return as we can't do anything now
		}

		//Marshaling the packets into databytes for sending:
		data, err := proto.Marshal(packet)
		//checkin for any errros while marshaling (serializing):
		if err != nil {
			c.logger.Printf("Error marshaling %T packet, closing client: %v", packet.Msg, err)
			continue
		}

		_, err = writer.Write(data) //writing the data
		if err != nil {
			c.logger.Printf("Error writing %T packet, closing client: %v", packet.Msg, err)
			continue
		}

		//going to the next line after writing data
		writer.Write([]byte{'\n'})

		//closing:
		if err = writer.Close(); err != nil {
			c.logger.Printf("Error closing writer for %T packet: %v", packet.Msg, err)
			continue
		}

	}
}

// Closing function
func (c *WebSocketClient) Close(reason string) {
	c.logger.Printf("Closing client connection because: %s", reason)

	c.hub.UnregisterChan <- c
	c.conn.Close()
	if _, closed := <-c.sendChan; !closed {
		close(c.sendChan)
	}
}
