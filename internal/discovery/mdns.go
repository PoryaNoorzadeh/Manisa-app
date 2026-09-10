package discovery

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"

	"github.com/grandcat/zeroconf"
)

const ServiceType = "_manisa._tcp"

type Advertiser struct {
	server *zeroconf.Server
}

func Start(httpAddr string) (*Advertiser, error) {
	port, err := portFromAddr(httpAddr)
	if err != nil {
		return nil, err
	}

	hostname, _ := os.Hostname()
	instance := "Manisa Hub"
	if trimmed := strings.TrimSpace(hostname); trimmed != "" {
		instance += " " + trimmed
	}

	server, err := zeroconf.Register(
		instance,
		ServiceType,
		"local.",
		port,
		[]string{
			"api=1",
			"local_first=1",
			"path=/api/v1",
			"events=/api/v1/events",
		},
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("advertise Manisa hub over mDNS: %w", err)
	}
	return &Advertiser{server: server}, nil
}

func (a *Advertiser) Close() {
	if a != nil && a.server != nil {
		a.server.Shutdown()
	}
}

func portFromAddr(addr string) (int, error) {
	_, portText, err := net.SplitHostPort(addr)
	if err != nil {
		return 0, fmt.Errorf("parse HTTP address %q for mDNS: %w", addr, err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 1 || port > 65535 {
		return 0, fmt.Errorf("invalid HTTP port %q", portText)
	}
	return port, nil
}
