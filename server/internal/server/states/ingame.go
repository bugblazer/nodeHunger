package states

import (
	"context"
	"fmt"
	"log"
	"math"
	"math/rand"
	"server/internal/server"
	"server/internal/server/db"
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
	g.player.X, g.player.Y = objects.SpawnCoords(g.player.Radius, g.client.SharedGameObjects().Players, nil)
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
	case *packets.Packet_PlayerConsumed:
		g.handlePlayerConsumed(senderId, message)
	case *packets.Packet_Spore:
		g.handleSpore(senderId, message)
	case *packets.Packet_Disconnect:
		g.handleDisconnect(senderId, message)
	}
}

// To cleanup once the player leaves and free up memory
func (g *InGame) OnExit() {
	if g.cancelPlayerUpdateLoop != nil {
		g.cancelPlayerUpdateLoop()
	}
	g.client.SharedGameObjects().Players.Remove(g.client.Id())
	g.syncPlayerBestScore()
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
			go g.playerUpdateLoop(ctx)
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
	//If the info is coming from another client, it means the checks were already performed on
	//that client's server side. So we'll forward the message to godot directly
	if senderId != g.client.Id() {
		g.client.SocketSendAs(message, senderId)
		return
	}

	//If the spore was consumed by our player, we'll have to verify
	errMsg := "Could not verify spore consumption: "

	//First, checking if the spore exists
	sporeId := message.SporeConsumed.SporeId
	spore, err := g.getSpore(sporeId)
	if err != nil {
		g.logger.Println(errMsg + err.Error())
		return
	}

	//Now checkin if the spore is close enough to be consumed
	err = g.validatePlayerCloseToObjects(spore.X, spore.Y, spore.Radius, 10)
	if err != nil {
		g.logger.Println(errMsg + err.Error())
		return
	}

	//Finally, check if the spore wasn't dropped by the player too recently
	err = g.validatePlayerDropCooldown(spore, 10)
	if err != nil {
		g.logger.Println(errMsg + err.Error())
		return
	}

	//If we make it this far, it means the spore consumption is valid, so we'll grow the player
	//and remove the spore as well as broadcast the event
	sporeMass := radToMass(spore.Radius)
	g.player.Radius = g.nextRadius(sporeMass)

	go g.client.SharedGameObjects().Spores.Remove(sporeId)

	g.client.Broadcast(message)

	// Syncing the best scores after player eats spores in a go routine because it'll involve DB operations
	go g.syncPlayerBestScore()
}

// Function to handle the consumption of player on server side
func (g *InGame) handlePlayerConsumed(senderId uint64, message *packets.Packet_PlayerConsumed) {
	//No need to verify it if it came from another player since it was already verified on that player's side
	if senderId != g.client.Id() {
		g.client.SocketSendAs(message, senderId)

		if message.PlayerConsumed.PlayerId == g.client.Id() {
			g.logger.Println("Player was consumed, respawning")
			g.client.SetState(&InGame{
				player: &objects.Player{
					Name: g.player.Name,
				},
			})
		}

		return
	}

	//But if we're the one consuming, we need to verify
	errMsg := "Could not verify player consumtion: "

	//First checking if the player exists
	otherId := message.PlayerConsumed.PlayerId
	other, err := g.getOtherPlayer(otherId)
	if err != nil {
		g.logger.Println(errMsg + err.Error())
		return
	}

	//Checking if the other player's mass is 150% smaller than ours
	ourMass := radToMass(g.player.Radius)
	otherMass := radToMass(other.Radius)
	if ourMass <= otherMass*1.5 {
		g.logger.Printf(errMsg+"player not massive enough to consume the other player (our radius: %f, other radius: %f)", g.player.Radius, other.Radius)
		return
	}

	//Lastly checking if the player was close enough
	err = g.validatePlayerCloseToObjects(other.X, other.Y, other.Radius, 10)
	if err != nil {
		g.logger.Println(errMsg + err.Error())
		return
	}

	//If we make it this far, it means everything is valid, we'll grow the player and broadcast the event
	g.player.Radius = g.nextRadius(otherMass)

	go g.client.SharedGameObjects().Players.Remove(otherId)

	g.client.Broadcast(message)

	// Syncing the best scores after player eats someone in a go routine because it'll involve DB operations
	go g.syncPlayerBestScore()
}

func (g *InGame) handleSpore(senderId uint64, message *packets.Packet_Spore) {
	g.client.SocketSendAs(message, senderId)
}

func (g *InGame) handleDisconnect(senderId uint64, message *packets.Packet_Disconnect) {
	if senderId == g.client.Id() {
		g.client.Broadcast(message)
		g.client.SetState(&Connected{})
		return
	}

	go g.client.SocketSendAs(message, senderId)
}

// Function to keep running syncPlayer in a loop
// It takes context as a parameter so the loop knows when to stop
func (g *InGame) playerUpdateLoop(ctx context.Context) {
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

	//Drop a spore
	probability := g.player.Radius / float64(server.MaxSpores*5)
	if rand.Float64() < probability && g.player.Radius > 10 {
		spore := &objects.Spore{
			X:         g.player.X,
			Y:         g.player.Y,
			Radius:    min(5+g.player.Radius/50, 15),
			DroppedBy: g.player,
			DroppedAt: time.Now(),
		}
		sporeId := g.client.SharedGameObjects().Spores.Add(spore)
		g.client.Broadcast(packets.NewSpore(sporeId, spore))
		go g.client.SocketSend(packets.NewSpore(sporeId, spore))
		g.player.Radius = g.nextRadius(-radToMass(spore.Radius))
	}

	//Broadcasting the updated player state
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

// Function to check if a spore even exists (hacking prevention)
func (g *InGame) getSpore(sporeId uint64) (*objects.Spore, error) {
	spore, exists := g.client.SharedGameObjects().Spores.Get(sporeId)
	if !exists {
		return nil, fmt.Errorf("spore with the id %d does not exist", sporeId)
	}
	return spore, nil
}

// Function to check if the other player even exists
func (g *InGame) getOtherPlayer(playerId uint64) (*objects.Player, error) {
	player, exists := g.client.SharedGameObjects().Players.Get(playerId)
	if !exists {
		return nil, fmt.Errorf("plaer with the id %d does not exist", playerId)
	}
	return player, nil
}

// Function to check if the player was close enough to the spore/ other player to consume it
func (g *InGame) validatePlayerCloseToObjects(objX, objY, objRadius, buffer float64) error {
	realDX := g.player.X - objX
	realDY := g.player.Y - objY
	realDistSq := realDX*realDX + realDY*realDY

	thresholdDist := g.player.Radius + buffer + objRadius
	thresholdDistSq := thresholdDist * thresholdDist

	if realDistSq > thresholdDistSq {
		return fmt.Errorf("player is too far from the object (distSq: %f, thresholdSq: %f)", realDistSq, thresholdDistSq)
	}
	return nil
}

func (g *InGame) validatePlayerDropCooldown(spore *objects.Spore, buffer float64) error {
	minAcceptableDistance := spore.Radius + g.player.Radius - buffer
	minAcceptableTime := time.Duration(minAcceptableDistance/g.player.Speed*1000) * time.Millisecond
	if spore.DroppedBy == g.player && time.Since(spore.DroppedAt) < minAcceptableTime {
		return fmt.Errorf("player dropped the spore too recently (time since drop: %v, min acceptable time: %v)", time.Since(spore.DroppedAt), minAcceptableTime)
	}
	return nil
}

func radToMass(radius float64) float64 {
	return math.Pi * radius * radius
}

func massToRad(mass float64) float64 {
	return math.Sqrt(mass / math.Pi)
}

func (g *InGame) nextRadius(massDiff float64) float64 {
	oldMass := radToMass(g.player.Radius)
	newMass := oldMass + massDiff
	return massToRad(newMass)
}

func (g *InGame) syncPlayerBestScore() {
	currentScore := int64(math.Round(radToMass(g.player.Radius)))
	if currentScore > g.player.BestScore {
		g.player.BestScore = currentScore
		err := g.client.DbTx().Queries.UpdatePlayerBestScore(g.client.DbTx().Ctx, db.UpdatePlayerBestScoreParams{
			ID:        g.player.DbId,
			BestScore: g.player.BestScore,
		})

		if err != nil {
			g.logger.Printf("Error updating the player best score: %v", err)
		}
	}
}
