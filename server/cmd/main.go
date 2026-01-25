package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"server/internal/server"
	"server/internal/server/clients"
)

var (
	port = flag.Int("port", 8000, "Port to listen on")
)

func main() {
	flag.Parse()

	// Defining the game hub
	hub := server.NewHub()

	// Defining handler for WebSocket connections
	//Using "ws"(web socket) route, allowing full duplex communication
	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		hub.Serve(clients.NewWebSocketClient, w, r)
	})
	//^Now whenever a new connection is and the client tries to access ws route, it will
	//serve the new connection with the hub by creating a new websocket connection and start
	//processing requests

	//Now that the handler is defined, let's run (start) the hub using a go routine to make sure the hub
	//can always run in the background
	go hub.Run()

	//Since the hub started, now we need to actually listen to the port
	addr := fmt.Sprintf(":%d", *port) //default port 8080

	log.Printf("Starting server on %s", addr)
	err := http.ListenAndServe(addr, nil)

	//In case of an error, print a fatal error message which will stop the server:
	if err != nil {
		log.Fatalf("Failed to start the server: %v", err)
	}

}
