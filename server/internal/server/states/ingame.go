package states

import (
	"context"
	"fmt"
	"log"
	"math"
	"math/rand"
	"server/internal/server"
	"server/internal/server/objects"
	"server/pkg/packets"
	"time"
)

// Structure that defines the elements of ingame state
type InGame struct {
	client                 server.ClientInterfacer
	player                 *objects.Player
	logger                 *log.Logger
	cancelPlayerUpdateLoop context.CancelFunc
}

//The functions below are here to satisfy the constructor of ClientStateHandler in Hub.gp

// Function that returns the name of the state
func (g *InGame) Name() string {
	return "InGame"
}

// Function that sets the client for the game, it gives the client to the game object (g)
// It also logs the client id and name
func (g *InGame) SetClient(client server.ClientInterfacer) {
	g.client = client
	loggingPrefix := fmt.Sprintf("Client %d [%s]: ", client.Id(), g.Name())
	g.logger = log.New(log.Writer(), loggingPrefix, log.LstdFlags)
}

// Function that defines what happens when player enters the game, it logs a message and
// then it adds the said player in the SharedGameObjects
// the go keyword makes sure the process is performed even when the object is locked
func (g *InGame) OnEnter() {
	g.logger.Printf("Adding player %s to the shared collection", g.player.Name)
	go g.client.SharedGameObjects().Players.Add(g.player, g.client.Id())

	//Setting the initial player properties such as mass, position etc
	g.player.X = rand.Float64() * 1000
	g.player.Y = rand.Float64() * 1000
	g.player.Speed = 150.0
	g.player.Radius = 25

	//Sending the initial state of the player to the client
	g.client.SocketSend(packets.NewPlayer(g.client.Id(), g.player))

	//Sending the spores to the client in the background using go routines
	go g.sendInitialSpores(20, 50*time.Millisecond)
}

// Handling chat
func (g *InGame) HandleMessage(senderId uint64, message packets.Msg) {
	switch message := message.(type) {
	case *packets.Packet_Player:
		g.handlePlayer(senderId, message) //ignores the message if the client and sender IDs are same
	case *packets.Packet_PlayerDirection:
		g.handlePlayerDirection(senderId, message)
	case *packets.Packet_Chat:
		g.HandleChat(senderId, message)
	case *packets.Packet_SporeConsumed:
		g.handleSporeConsumed(senderId, message)
	}
}

// To cleanup once the player leaves and free up memory
func (g *InGame) OnExit() {
	if g.cancelPlayerUpdateLoop != nil {
		g.cancelPlayerUpdateLoop()
	}
	g.client.SharedGameObjects().Players.Remove(g.client.Id())
}

// Function to log if sender id and client id match
func (g *InGame) handlePlayer(senderId uint64, message *packets.Packet_Player) {
	if senderId == g.client.Id() {
		g.logger.Println("Recoeved player messages from our own client, ignoring")
		return
	}

	g.client.SocketSendAs(message, senderId)
}

// Function to
func (g *InGame) handlePlayerDirection(senderId uint64, message *packets.Packet_PlayerDirection) {
	if senderId == g.client.Id() {
		g.player.Direction = message.PlayerDirection.Direction

		//If it's the first time recieveing direction updates from the player, we'll start the
		//UpdatePlayerDirectionLoop
		if g.cancelPlayerUpdateLoop == nil {
			ctx, cancel := context.WithCancel(context.Background())
			g.cancelPlayerUpdateLoop = cancel
			go g.updatePlayerLoop(ctx)
		}
	}
}

func (g *InGame) HandleChat(senderId uint64, message *packets.Packet_Chat) {
	if senderId == g.client.Id() {
		g.client.Broadcast(message)
	} else {
		g.client.SocketSendAs(message, senderId)
	}
}

func (g *InGame) handleSporeConsumed(senderId uint64, message *packets.Packet_SporeConsumed) {
	g.logger.Printf("Spore %d consumed by player", message.SporeConsumed.SporeId)
}

// Function to keep running syncPlayer in a loop
// It takes context as a parameter so the loop knows when to stop
func (g *InGame) updatePlayerLoop(ctx context.Context) {
	const delta float64 = 0.05 //The syncPlayer method will run 20 times per second
	ticker := time.NewTicker(time.Duration(delta*1000) * time.Millisecond)
	//ticker allows us to run something in equal intervals
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			g.syncPlayer(delta)
		case <-ctx.Done():
			return //return once the context has been fulfilled
		}
	}
}

// keep track of player movement on the server side
// delta is the time passed since we last synced the player
// with the server
func (g *InGame) syncPlayer(delta float64) {
	newX := g.player.X + g.player.Speed*math.Cos(g.player.Direction)*delta
	newY := g.player.Y + g.player.Speed*math.Sin(g.player.Direction)*delta

	g.player.X = newX
	g.player.Y = newY

	updatePacket := packets.NewPlayer(g.client.Id(), g.player)
	g.client.Broadcast(updatePacket)
	go g.client.SocketSend(updatePacket)
}

func (g *InGame) sendInitialSpores(batchSize int, delay time.Duration) {
	sporesBatch := make(map[uint64]*objects.Spore, batchSize)

	g.client.SharedGameObjects().Spores.ForEach(func(sporeId uint64, spore *objects.Spore) {
		sporesBatch[sporeId] = spore

		if len(sporesBatch) >= batchSize {
			g.client.SocketSend(packets.NewSporeBatch(sporesBatch))
			sporesBatch = make(map[uint64]*objects.Spore, batchSize)
			time.Sleep(delay)
		}
	})

	//Sending any remaining spores
	if len(sporesBatch) > 0 {
		g.client.SocketSend(packets.NewSporeBatch(sporesBatch))
	}
}
