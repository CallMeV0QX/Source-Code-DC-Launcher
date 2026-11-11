// SPDX-License-Identifier: GPL-3.0-only
package steamdns

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

type cacheEntry struct {
	bytes   []byte
	expires time.Time
}
type Resolver struct {
	client    *http.Client
	endpoints []string
	mu        sync.Mutex
	cache     map[string]cacheEntry
}

func NewResolver() *Resolver {
	transport := &http.Transport{Proxy: nil, MaxIdleConns: 8, MaxIdleConnsPerHost: 4,
		IdleConnTimeout: 30 * time.Second, TLSHandshakeTimeout: 4 * time.Second,
		ResponseHeaderTimeout: 4 * time.Second, ForceAttemptHTTP2: true,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(address)
			if err != nil {
				return nil, err
			}
			// Bootstrap only fixed DoH providers; TLS still validates the URL name.
			switch host {
			case "cloudflare-dns.com":
				host = "1.1.1.1"
			case "dns.google":
				host = "8.8.8.8"
			default:
				return nil, errors.New("unapproved DNS upstream")
			}
			return (&net.Dialer{Timeout: 3 * time.Second}).DialContext(ctx, network, net.JoinHostPort(host, port))
		}}
	return &Resolver{client: &http.Client{Transport: transport, Timeout: 5 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("DNS redirect refused") }},
		endpoints: []string{"https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"}, cache: make(map[string]cacheEntry)}
}

func (r *Resolver) Clear() {
	r.mu.Lock()
	r.cache = make(map[string]cacheEntry)
	r.mu.Unlock()
	r.client.CloseIdleConnections()
}

func (r *Resolver) Check(ctx context.Context) error {
	query := []byte{0x4e, 0x47, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 14, 's', 't', 'e', 'a', 'm', 'c', 'o', 'm', 'm', 'u', 'n', 'i', 't', 'y', 3, 'c', 'o', 'm', 0, 0, 1, 0, 1}
	reply := r.Resolve(ctx, query)
	if len(reply) < 12 || reply[3]&15 != 0 || binary.BigEndian.Uint16(reply[6:8]) == 0 {
		return errors.New("dns-upstream-unavailable")
	}
	return nil
}

func (r *Resolver) Resolve(ctx context.Context, query []byte) []byte {
	q, err := parseQuestion(query)
	if err != nil || len(query) > 4096 || query[2]&0xf8 != 0 || q.class != 1 || q.kind == 255 {
		return failure(query, 1)
	}
	if !Allowed(q.name) {
		return failure(query, 5)
	}
	// Cache only simple questions. EDNS flags/options must reach upstream intact.
	key := q.name + string([]byte{byte(q.kind >> 8), byte(q.kind), query[2], query[3]})
	cacheable := len(query) == q.end
	if cacheable {
		r.mu.Lock()
		entry, exists := r.cache[key]
		r.mu.Unlock()
		if exists && time.Now().Before(entry.expires) {
			reply := append([]byte(nil), entry.bytes...)
			copy(reply[:2], query[:2])
			return reply
		}
	}
	for _, endpoint := range r.endpoints {
		request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(query))
		if err != nil {
			continue
		}
		request.Header.Set("Content-Type", "application/dns-message")
		request.Header.Set("Accept", "application/dns-message")
		response, err := r.client.Do(request)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			continue
		}
		body, readErr := io.ReadAll(io.LimitReader(response.Body, 65536))
		response.Body.Close()
		if readErr != nil || response.StatusCode != http.StatusOK || response.Header.Get("Content-Type") != "application/dns-message" {
			continue
		}
		ttl, err := validateReply(query, body)
		if err != nil || body[3]&15 == 2 {
			continue
		}
		copy(body[:2], query[:2])
		if cacheable && ttl > 0 {
			r.mu.Lock()
			if len(r.cache) >= 256 {
				r.cache = make(map[string]cacheEntry)
			}
			r.cache[key] = cacheEntry{append([]byte(nil), body...), time.Now().Add(time.Duration(ttl) * time.Second)}
			r.mu.Unlock()
		}
		return body
	}
	return failure(query, 2)
}

type Relay struct {
	resolver *Resolver
	udp      *net.UDPConn
	tcp      net.Listener
	ctx      context.Context
	cancel   context.CancelFunc
	gate     chan struct{}
	wg       sync.WaitGroup
	healthy  atomic.Bool
}

// Production passes 127.0.0.1:53. Tests use a loopback ephemeral port and never
// write NRPT, DNS adapter settings, firewall rules or driver state.
func StartRelay(resolver *Resolver, address string) (*Relay, error) {
	parsed, err := net.ResolveUDPAddr("udp4", address)
	if err != nil || !parsed.IP.IsLoopback() {
		return nil, errors.New("DNS listener must be loopback")
	}
	udp, err := net.ListenUDP("udp4", parsed)
	if err != nil {
		return nil, err
	}
	tcp, err := net.Listen("tcp4", udp.LocalAddr().String())
	if err != nil {
		udp.Close()
		return nil, err
	}
	ctx, cancel := context.WithCancel(context.Background())
	r := &Relay{resolver: resolver, udp: udp, tcp: tcp, ctx: ctx, cancel: cancel, gate: make(chan struct{}, 32)}
	r.healthy.Store(true)
	r.wg.Add(2)
	go r.serveUDP()
	go r.serveTCP()
	return r, nil
}

func (r *Relay) Healthy() bool { return r != nil && r.healthy.Load() }
func (r *Relay) Close() {
	if r == nil {
		return
	}
	r.healthy.Store(false)
	r.cancel()
	r.udp.Close()
	r.tcp.Close()
	r.wg.Wait()
	r.resolver.Clear()
}

func (r *Relay) serveUDP() {
	defer r.wg.Done()
	defer r.healthy.Store(false)
	for {
		buffer := make([]byte, 4097)
		count, peer, err := r.udp.ReadFromUDP(buffer)
		if err != nil {
			return
		}
		if count > 4096 || !peer.IP.IsLoopback() {
			continue
		}
		query := buffer[:count]
		select {
		case r.gate <- struct{}{}:
			r.wg.Add(1)
			go func() {
				defer r.wg.Done()
				defer func() { <-r.gate }()
				ctx, cancel := context.WithTimeout(r.ctx, 11*time.Second)
				defer cancel()
				reply := r.resolver.Resolve(ctx, query)
				if len(reply) > 512 {
					reply = failure(query, 0)
					if len(reply) > 3 {
						reply[2] |= 2
					}
				}
				if len(reply) > 0 {
					_, _ = r.udp.WriteToUDP(reply, peer)
				}
			}()
		default:
			if reply := failure(query, 2); len(reply) > 0 {
				_, _ = r.udp.WriteToUDP(reply, peer)
			}
		}
	}
}

func (r *Relay) serveTCP() {
	defer r.wg.Done()
	defer r.healthy.Store(false)
	for {
		connection, err := r.tcp.Accept()
		if err != nil {
			return
		}
		select {
		case r.gate <- struct{}{}:
			r.wg.Add(1)
			go func() {
				defer r.wg.Done()
				defer func() { <-r.gate }()
				defer connection.Close()
				stop := context.AfterFunc(r.ctx, func() { connection.Close() })
				defer stop()
				for index := 0; index < 16; index++ {
					_ = connection.SetDeadline(time.Now().Add(12 * time.Second))
					size := make([]byte, 2)
					if _, err := io.ReadFull(connection, size); err != nil {
						return
					}
					count := int(binary.BigEndian.Uint16(size))
					if count < 12 || count > 4096 {
						return
					}
					query := make([]byte, count)
					if _, err := io.ReadFull(connection, query); err != nil {
						return
					}
					ctx, cancel := context.WithTimeout(r.ctx, 11*time.Second)
					reply := r.resolver.Resolve(ctx, query)
					cancel()
					if len(reply) < 12 {
						return
					}
					binary.BigEndian.PutUint16(size, uint16(len(reply)))
					if _, err := connection.Write(append(size, reply...)); err != nil {
						return
					}
				}
			}()
		default:
			connection.Close()
		}
	}
}
