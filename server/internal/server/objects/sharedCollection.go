package objects

import (
	"sync"
)

// Creating the custom data structure:
type SharedCollection[T any] struct {
	objectsMap map[uint64]T
	nextId     uint64
	mapMux     sync.Mutex //allows us to lock resources
}

// Constructor for the SharedCollection:
// It initializes the struct safely cause we have a map in it
// maps can't be initialized normally, they need a reference
func NewSharedCollection[T any](capacity ...int) *SharedCollection[T] {
	var newObjMap map[uint64]T

	if len(capacity) > 0 {
		newObjMap = make(map[uint64]T, capacity[0])
	} else {
		newObjMap = make(map[uint64]T)
	}

	return &SharedCollection[T]{
		objectsMap: newObjMap,
		nextId:     1,
	}
}

// A method to add objects to the shared collection
// It'll add an object with its ID (if given), otherwise it'll give the next available ID
// Returns the ID of the obj
func (s *SharedCollection[T]) Add(obj T, id ...uint64) uint64 {
	s.mapMux.Lock()         //lock the map to avoid any ID bugs
	defer s.mapMux.Unlock() //Unlock the map once the function has finished running

	thisId := s.nextId //sets the ID to shared collection's next id
	if len(id) > 0 {
		thisId = id[0] //but if we specified an ID in func argument, then assign that ID
	}

	s.objectsMap[thisId] = obj //After all the above working, the object provided to the func is stored in map
	s.nextId++

	return thisId //returns ID of the obj stored
}

// Method for removing objects from shared collection
// takes the ID of the obj to be removed
func (s *SharedCollection[T]) Remove(id uint64) {
	s.mapMux.Lock()         //locking again to avoid multithreading issues
	defer s.mapMux.Unlock() //unlock once the function is done running

	delete(s.objectsMap, id)
}

// Mehtod to loop through every obj in the map
// calls the callback func for each obj in the map
// For each element call the below func
func (s *SharedCollection[T]) ForEach(callback func(uint64, T)) {
	//Going to lock the collection, make a local copy and then unlock
	//Loop takes some time, keeping the collection locked for that whole time stops
	//adding and deleting objs procrss
	//Learned this the hard way :')
	s.mapMux.Lock()
	localCopy := make(map[uint64]T, len(s.objectsMap))
	for id, obj := range s.objectsMap {
		localCopy[id] = obj
	}
	s.mapMux.Unlock()

	//Now looping over the local copy while the original collection is free for other methods
	for id, obj := range localCopy {
		callback(id, obj)
	}
}

// Method to get an obj from the map
// takes an ID and returns the obj if it exists otherwise ret nil
// also returns t/f based on the obj existing in the map or not
func (s *SharedCollection[T]) Get(id uint64) (T, bool) {
	s.mapMux.Lock()
	defer s.mapMux.Unlock()

	obj, found := s.objectsMap[id]
	return obj, found
}

// Method to get the number of objects in the collection
// not locking because I don't think it's worth it to lock and slow down
// an approximate should do just fine
func (s *SharedCollection[T]) len() int {
	return len(s.objectsMap)
}
