package steamdns

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"os"
	"testing"
	"time"
)

// Opt-in, read-only: fixed public Steam requests with per-request DNS. No NRPT,
// driver, WARP, adapter, certificate, account or Steam installation mutation.
func TestReadOnlyRealSteamHTTPSUsingEncryptedDNS(t *testing.T) {
	if os.Getenv("DC_STEAM_DNS_NETWORK_TEST") != "1" {
		t.Skip("read-only network check is opt-in")
	}
	resolver := NewResolver()
	ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
	defer cancel()
	if err := resolver.Check(ctx); err != nil {
		t.Fatal(err)
	}
	for _, target := range []struct {
		host, path string
		image      bool
	}{{"steamcommunity.com", "/login/home/", false}, {"store.steampowered.com", "/", false}, {"cdn.akamai.steamstatic.com", "/steam/apps/730/header.jpg", true}} {
		reply := resolver.Resolve(ctx, queryFor(target.host, 1))
		q, err := parseQuestion(reply)
		if err != nil || reply[3]&15 != 0 {
			t.Fatal("encrypted DNS failed")
		}
		address := ""
		offset := q.end
		for index := 0; index < int(binary.BigEndian.Uint16(reply[6:8])); index++ {
			_, end, err := nameAt(reply, offset)
			if err != nil {
				t.Fatal(err)
			}
			size := int(binary.BigEndian.Uint16(reply[end+8 : end+10]))
			start := end + 10
			if binary.BigEndian.Uint16(reply[end:end+2]) == 1 && size == 4 {
				address = net.IP(reply[start : start+4]).String()
				break
			}
			offset = start + size
		}
		if address == "" {
			t.Fatal("no public IPv4 answer")
		}
		transport := &http.Transport{Proxy: nil, TLSHandshakeTimeout: 5 * time.Second, ResponseHeaderTimeout: 5 * time.Second,
			DialContext: func(ctx context.Context, network, destination string) (net.Conn, error) {
				return (&net.Dialer{Timeout: 5 * time.Second}).DialContext(ctx, "tcp4", net.JoinHostPort(address, "443"))
			}}
		client := &http.Client{Transport: transport, Timeout: 8 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
		request, _ := http.NewRequestWithContext(ctx, http.MethodGet, "https://"+target.host+target.path, nil)
		request.Header.Set("User-Agent", "DCGaming-SteamConnectivity/1.0")
		response, err := client.Do(request)
		if err != nil {
			transport.CloseIdleConnections()
			t.Fatalf("%s: %v", target.host, err)
		}
		if response.StatusCode != 200 {
			response.Body.Close()
			t.Fatalf("%s: HTTP %d", target.host, response.StatusCode)
		}
		if target.image {
			var prefix [16]byte
			if _, err = io.ReadFull(response.Body, prefix[:]); err != nil || prefix[0] != 255 || prefix[1] != 216 || prefix[2] != 255 {
				response.Body.Close()
				t.Fatal("invalid JPEG")
			}
		}
		response.Body.Close()
		transport.CloseIdleConnections()
		t.Logf("%s HTTP 200; TLS verified; fixed DNS only", target.host)
	}
}
