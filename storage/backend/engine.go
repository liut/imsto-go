package backend

import (
	"errors"
	"github.com/go-imsto/imsto/config"
	"github.com/go-imsto/imsto/storage/types"
	"strings"
)

type JsonKV = types.JsonKV

type FarmFunc func(string) (Wagoner, error)

type engine struct {
	name string
	farm FarmFunc
}

const (
	minIDLength = 8
)

type Wagoner interface {
	Get(id string) ([]byte, error)
	Put(id string, data []byte, meta JsonKV) (JsonKV, error)
	Exists(id string) (bool, error)
	Del(id string) error
}

var engines = make(map[string]engine)

// Register a Engine
func RegisterEngine(name string, farm FarmFunc) {
	if farm == nil {
		panic("imsto: Register engine is nil")
	}
	if _, dup := engines[name]; dup {
		panic("imsto: Register called twice for engine " + name)
	}
	engines[name] = engine{name, farm}
}

// get a intance of Wagoner by a special config name
func FarmEngine(roof string) (Wagoner, error) {
	name := config.GetValue(roof, "engine")
	if engine, ok := engines[name]; ok {
		return engine.farm(roof)
	}

	return nil, errors.New("invalid engine name: " + name)
}

func Id2Path(r string) string {
	if len(r) < minIDLength || strings.Index(r, "/") > 0 { // > -1 表示有
		return r
	}
	return r[0:2] + "/" + r[2:4] + "/" + r[4:]
}
