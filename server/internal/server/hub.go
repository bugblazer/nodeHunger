package server

import (
	"log"
	"net/http"
	"server/pkg/packets"
)

type ClientInterfacer interface {
	//Returns client ID
	Id() uint64

	//This method takes in a sender ID and the sender's message
	ProcessMessage(senderId uint64, message packets.Msg)

	//Setting client ID
	Initialize(id uint64)

	//Puts data from the current client to the WritePump
	SocketSend(message packets.Msg)

	//Puts data from another client to the WritePump
	SocketSendAs(message packets.Msg, senderId uint64)

	//Forward message to another client for processing
	PassToPeer(message packets.Msg, senderId uint64)

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
	Clients map[uint64]ClientInterfacer

	//The packets in this channel will be sent over to all connected clients
	BroadcastChan chan *packets.Packet

	//Channel for registering new clients
	RegisterChan chan ClientInterfacer

	//Channel for unregistering the clients
	UnregisterChan chan ClientInterfacer
}

// Constructor for the Hub:
func newHub() *Hub {
	return &Hub{
		Clients:        make(map[uint64]ClientInterfacer),
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
			client.Initialize(uint64(len(h.Clients))) //setting the client ID to it's
			//index number in the map (for now)

		case client := <-h.UnregisterChan:
			h.Clients[client.Id()] = nil //Not deleting the client to maintain
			//proper numbering(0-n), instead setting
			//it to nil

		case packet := <-h.BroadcastChan:
			for id, client := range h.Clients {
				if id != packet.SenderId {
					client.ProcessMessage(packet.SenderId, packet.Msg)
				}
			}
			//This last case takes any packet sent to the broadcast channel, then it
			//loops through each client in our map (named Clients)
			//As long as the client ID is not same as the packet sender ID
			//the message is processed by the client

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
