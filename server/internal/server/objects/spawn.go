package objects

import "math/rand"

var getPlayerPosition = func(p *Player) (float64, float64) { return p.X, p.Y }
var getPlayerRadius = func(p *Player) float64 { return p.Radius }

var getSporePosition = func(s *Spore) (float64, float64) { return s.X, s.Y }
var getSporeRadius = func(s *Spore) float64 { return s.Radius }

func isTooClose[T any](x float64, y float64, radius float64, objects *SharedCollection[T], getPosition func(T) (float64, float64), getRadius func(T) float64) bool {
	//Check there are not any objects
	if objects == nil {
		return false
	}

	//Check if any object is too close
	tooClose := false
	objects.ForEach(func(_ uint64, object T) {
		if tooClose {
			return
		}

		//pythagoras theorem
		objX, objY := getPosition(object)
		objRad := getRadius(object)
		xDst := objX - x
		yDist := objY - y
		dstSq := xDst*xDst + yDist*yDist

		if dstSq <= (radius+objRad)*(radius+objRad) {
			tooClose = true
			return
		}
	})

	return tooClose
}

func SpawnCoords(radius float64, playersToAvoid *SharedCollection[*Player], sporesToAvoid *SharedCollection[*Spore]) (float64, float64) {
	var bound float64 = 3000. //max coords limit
	const maxTries int = 25

	tries := 0

	for {
		x := bound * (2*rand.Float64() - 1) //Generating x and y coords in an infinite loop
		y := bound * (2*rand.Float64() - 1)

		//if the coords are not too close to another player or spores then assigns the coords
		//otherwise generate coords again, if the max tries have been reached, we increase the
		//max coord boundary and make it double
		if !isTooClose(x, y, radius, playersToAvoid, getPlayerPosition, getPlayerRadius) &&
			!isTooClose(x, y, radius, sporesToAvoid, getSporePosition, getSporeRadius) {
			return x, y
		}
		tries++
		if tries >= maxTries {
			bound *= 2
			tries = 0
		}
	}
}
