package server

import (
	"log"
	"net/http"
	"server/internal/server/objects"
	"server/pkg/packets"
)

// A structure for the state machine to process client side messages
type ClientStateHandler interface {
	Name() string

	//Inject the client into the state handler, tells the state handler which client owns it
	SetClient(client ClientInterfacer)

	OnEnter()                                           //Method that gets called on entry
	HandleMessage(senderId uint64, message packets.Msg) //Handles the messages based on state
	OnExit()                                            //Opposite of OnEnter, does cleanup
}

type ClientInterfacer interface {
	//Returns client ID
	Id() uint64

	//This method takes in a sender ID and the sender's message
	ProcessMessage(senderId uint64, message packets.Msg)

	//Setting client ID
	Initialize(id uint64)

	//Setting states
	SetState(newState ClientStateHandler)

	//Puts data from the current client to the WritePump
	SocketSend(message packets.Msg)

	//Puts data from another client to the WritePump
	SocketSendAs(message packets.Msg, senderId uint64)

	//Forward message to another client for processing
	PassToPeer(message packets.Msg, peerId uint64)

	//Forward message to all other clients
	Broadcast(message packets.Msg)

	//Pumps data from the client to the connected socket
	ReadPump()

	//Pumps data from the connected socket to the client
	WritePump()

	//Closing client connection + cleanup
	Close(reason string) //passing in this parameter to know the reason behind closing
}

// The centerl communication b/w client and server:
type Hub struct {
	Clients *objects.SharedCollection[ClientInterfacer]

	//The packets in this channel will be sent over to all connected clients
	BroadcastChan chan *packets.Packet

	//Channel for registering new clients
	RegisterChan chan ClientInterfacer

	//Channel for unregistering the clients
	UnregisterChan chan ClientInterfacer
}

// Constructor for the Hub:
func NewHub() *Hub {
	return &Hub{
		Clients:        objects.NewSharedCollection[ClientInterfacer](),
		BroadcastChan:  make(chan *packets.Packet),
		RegisterChan:   make(chan ClientInterfacer),
		UnregisterChan: make(chan ClientInterfacer),
	}
}

// Creating a run method for Hub
// The method will listen to all the channels in Hub
// Like if it recieves a client interfacer frrom register channel
// the method will initialize the client, if recieved from unregister channel
// the method will remove that client from the map
// if it recieves a packet from broadcast channel, it will send the packet to
// all the clients
// (Also, the reason for using a select loop: if the Hub gets two requests, it'll select one,
// process it and then move to the other)
func (h *Hub) Run() {
	log.Println("Awaiting client registeration!")
	for {
		select {
		case client := <-h.RegisterChan:
			client.Initialize(h.Clients.Add(client)) //setting the client ID to it's
			//index number in the map (for now)

		case client := <-h.UnregisterChan:
			h.Clients.Remove(client.Id())

		case packet := <-h.BroadcastChan:
			// for id, client := range h.Clients {
			// 	if id != packet.SenderId {
			// 		client.ProcessMessage(packet.SenderId, packet.Msg)
			// 	}
			// }
			//This last case takes any packet sent to the broadcast channel, then it
			//loops through each client in our map (named Clients)
			//As long as the client ID is not same as the packet sender ID
			//the message is processed by the client
			//^Instead of the for in range loop, using a for each loop now after making the sharedCollection
			h.Clients.ForEach(func(clientId uint64, client ClientInterfacer) {
				if clientId != packet.SenderId {
					client.ProcessMessage(packet.SenderId, packet.Msg)
				}
			})

		}
	}
}

// Another Hub method, that has a function as its first argument
// Created a handler called getNewCleint which is a func itself
// It takes a reference to the Hub, http response writer and request
// The handler method returns a client interfacer and an error (if any)
// The second argument is a http writer and the last argument is a http requester
// This method will get called when we have a new connection from the socket
func (h *Hub) Serve(getNewClient func(*Hub, http.ResponseWriter, *http.Request) (ClientInterfacer, error),
	writer http.ResponseWriter, request *http.Request) {
	log.Println("New client connecting!", request.RemoteAddr)
	//^logs the message and remote address of the new client

	client, err := getNewClient(h, writer, request)

	if err != nil {
		log.Printf("Error getting cleint for the connection: %v", err)
		return //logs out the error message and returns from the function
	}

	//else
	h.RegisterChan <- client //registers the client

	go client.WritePump()
	go client.ReadPump()

	//^using the go keyword here so these processes will happen in the background thread
	//These two methods will be loops that will continuously read and write.
}
