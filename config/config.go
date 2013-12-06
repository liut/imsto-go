package config

import (
	"errors"
	"fmt"
	"github.com/vaughan0/go-ini"
	"log"
	"os"
	"path"
	"strconv"
	"strings"
)

const defaultConfigIni = `[common]
meta_dsn = postgres://imsto@localhost/imsto?sslmode=disable
;meta_table_suffix = demo
engine = s3
bucket_name = imsto-demo
max_quality = 88
max_file_size = 262114
max_width = 1600
max_height = 1600
min_width = 50
min_height = 50
thumb_path = /thumb
thumb_root = /opt/imsto/cache/thumb/
temp_root = /tmp/
support_size = 120,160,400
ticket_table = upload_ticket
watermark = watermark.png
watermark_opacity = 20
copyright = imsto.net
`

// var once sync.Once

var (
	cfgDir        string
	defaultConfig ini.File
	loadedConfig  ini.File
	thumbRoofs    = make(map[string]string)
)

func Root() string {
	return cfgDir
}

func SetRoot(dir string) {

	if _, err := os.Stat(dir); err != nil {
		log.Println(err)
		return
	}

	cfgDir = dir
}

func init() {
	defaultConfig, _ = ini.Load(strings.NewReader(defaultConfigIni))
}

func GetValue(section, name string) string {
	var (
		s  string
		ok bool
	)

	if s, ok = loadedConfig.Get(section, name); !ok {
		if s, ok = loadedConfig.Get("common", name); !ok {
			if s, ok = defaultConfig.Get("common", name); !ok {
				log.Printf("'%v' variable missing from '%v' section", name, section)
				return ""
			}
		}
	}

	return strings.Trim(s, "\"")
}

func GetInt(section, name string) int {
	s := GetValue(section, name)
	if i, err := strconv.ParseInt(s, 10, 64); err == nil {
		return int(i)
	}
	return 0
}

func GetSection(sname string) (section ini.Section) {
	if section = loadedConfig.Section(sname); len(section) > 0 {
		return section
	}

	return defaultConfig.Section("")
}

func HasSection(sname string) bool {
	if _, ok := loadedConfig[sname]; ok {
		return true
	}
	return false
}

// return administrable sections
func Sections() map[string]string {
	a := make(map[string]string)
	for k, v := range loadedConfig {
		if k != "common" {
			// a = append(a, k)
			if _, oka := v["administrable"]; oka {
				label, ok := v["label"]
				if !ok {
					label = strings.ToTitle(k)
				}
				a[k] = label
			}
		}
	}
	return a
}

func Load() (err error) {
	var dir string
	if cfgDir == "" {
		dir = os.Getenv("IMSTO_CONF")
		if dir == "" {
			err = errors.New("IMSTO_CONF not found in environment or -conf unset")
			return
		}
	} else {
		dir = cfgDir
	}
	cfgFile := path.Join(dir, "imsto.ini")

	loadedConfig, err = ini.LoadFile(cfgFile)

	if err != nil {
		// log.Print(err)
		return
	} /*else {
		log.Print("config loaded from " + cfgFile)
	}*/

	err = loadThumbRoofs()

	if err != nil {
		log.Printf("%s %s", err, cfgFile)
	}
	return
}

func loadThumbRoofs() error {
	for sec, _ := range Sections() {
		s := GetValue(sec, "thumb_path")
		tp := strings.TrimPrefix(s, "/")
		if _, ok := thumbRoofs[tp]; !ok {
			thumbRoofs[tp] = sec
		} else {
			return fmt.Errorf("duplicate 'thumb_path=%s' in config", s)
			// log.Printf("duplicate thumb_root in config")
		}
	}
	return nil
}

func ThumbRoof(s string) string {
	tp := strings.Trim(s, "/")
	if v, ok := thumbRoofs[tp]; ok {
		return v
	}
	return ""
}
