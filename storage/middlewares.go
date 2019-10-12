package storage

import (
	"context"
	"log"
	"net/http"

	"github.com/go-imsto/imagid"
)

// consts
const (
	DefaultMaxMemory = 12 << 20 // 8 MB
	APIKeyHeader     = "X-Access-Key"
)

// Delete ...
func Delete(roof, id string) error {
	if roof == "" {
		return ErrEmptyRoof
	}
	if id == "" {
		return ErrEmptyID
	}

	mw := NewMetaWrapper(roof)
	eid, err := imagid.ParseID(id)
	if err != nil {
		return err
	}
	err = mw.Delete(eid.String())
	if err != nil {
		return err
	}
	return nil
}

type ctxKey uint16

const (
	ctxAppKey ctxKey = iota
)

// CheckAPIKey ...
func CheckAPIKey(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		apiKey := r.Header.Get(APIKeyHeader)
		if apiKey == "" {
			apiKey = r.FormValue("api_key")
			if apiKey == "" {
				log.Print("Waring: parseRequest api_key is empty")
				w.WriteHeader(http.StatusBadRequest)
				return
			}
		}

		app, err := LoadApp(apiKey)
		if err != nil {
			log.Printf("arg 'api_key=%s' is invalid: %s", apiKey, err.Error())
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		ctx := context.WithValue(r.Context(), ctxAppKey, app)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// AppFromContext ...
func AppFromContext(ctx context.Context) (a *App, ok bool) {
	if v := ctx.Value(ctxAppKey); v != nil {
		a, ok = v.(*App)
	}
	return
}
