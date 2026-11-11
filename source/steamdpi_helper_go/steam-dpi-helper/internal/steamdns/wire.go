// SPDX-License-Identifier: GPL-3.0-only
package steamdns

import (
	"encoding/binary"
	"errors"
	"net/netip"
	"strings"
)

// These are namespaces, not URLs or user supplied rules. Other Windows DNS
// queries continue to use their original resolver. Exact names accompany
// suffixes because NRPT distinguishes a name from a namespace.
var Domains = []string{"steampowered.com", "steamcommunity.com", "steamstatic.com", "steamusercontent.com", "steamcontent.com", "steamgames.com", "steamserver.net", "steamcdn-a.akamaihd.net"}

func Namespaces() []string {
	var result []string
	for _, domain := range Domains {
		result = append(result, domain, "."+domain)
	}
	return result
}

func Allowed(name string) bool {
	name = strings.ToLower(strings.TrimSuffix(name, "."))
	for _, domain := range Domains {
		if name == domain || strings.HasSuffix(name, "."+domain) {
			return true
		}
	}
	return false
}

type question struct {
	name        string
	kind, class uint16
	end         int
}

func nameAt(message []byte, offset int) (string, int, error) {
	var parts []string
	end, length := -1, 0
	for steps := 0; steps < 128; steps++ {
		if offset >= len(message) {
			break
		}
		value := int(message[offset])
		offset++
		if value == 0 {
			if end < 0 {
				end = offset
			}
			return strings.ToLower(strings.Join(parts, ".")), end, nil
		}
		if value&0xc0 == 0xc0 {
			if offset >= len(message) {
				break
			}
			if end < 0 {
				end = offset + 1
			}
			offset = ((value & 63) << 8) | int(message[offset])
			continue
		}
		if value > 63 || value&0xc0 != 0 || offset+value > len(message) {
			break
		}
		length += value + 1
		if length > 254 {
			break
		}
		parts = append(parts, string(message[offset:offset+value]))
		offset += value
	}
	return "", 0, errors.New("invalid DNS name")
}

func parseQuestion(message []byte) (question, error) {
	if len(message) < 12 || binary.BigEndian.Uint16(message[4:6]) != 1 {
		return question{}, errors.New("invalid DNS question count")
	}
	name, end, err := nameAt(message, 12)
	if err != nil || end+4 > len(message) {
		return question{}, errors.New("invalid DNS question")
	}
	return question{name, binary.BigEndian.Uint16(message[end : end+2]), binary.BigEndian.Uint16(message[end+2 : end+4]), end + 4}, nil
}

func failure(query []byte, code byte) []byte {
	q, err := parseQuestion(query)
	if err != nil {
		return nil
	}
	result := append([]byte(nil), query[:q.end]...)
	result[2] = 0x81
	result[3] = 0x80 | code
	for index := 6; index < 12; index++ {
		result[index] = 0
	}
	return result
}

// Validate the entire bounded wire response, including compressed names and
// record lengths. Never serve private/loopback addresses returned upstream.
func validateReply(query, reply []byte) (uint32, error) {
	q, err := parseQuestion(query)
	if err != nil {
		return 0, err
	}
	r, err := parseQuestion(reply)
	if err != nil || r.name != q.name || r.kind != q.kind || r.class != q.class || len(reply) > 65535 || reply[0] != query[0] || reply[1] != query[1] || reply[2]&2 != 0 ||
		reply[2]&0x80 == 0 || reply[2]&0x78 != 0 || reply[3]&15 > 3 {
		return 0, errors.New("DNS reply mismatch")
	}
	count := int(binary.BigEndian.Uint16(reply[6:8])) + int(binary.BigEndian.Uint16(reply[8:10])) + int(binary.BigEndian.Uint16(reply[10:12]))
	if count > 1024 {
		return 0, errors.New("too many DNS records")
	}
	offset, ttl := r.end, uint32(60)
	for record := 0; record < count; record++ {
		_, end, err := nameAt(reply, offset)
		if err != nil || end+10 > len(reply) {
			return 0, errors.New("DNS record header")
		}
		kind := binary.BigEndian.Uint16(reply[end : end+2])
		size := int(binary.BigEndian.Uint16(reply[end+8 : end+10]))
		offset = end + 10
		if offset+size > len(reply) {
			return 0, errors.New("DNS record body")
		}
		if kind != 41 {
			if recordTTL := binary.BigEndian.Uint32(reply[end+4 : end+8]); recordTTL < ttl {
				ttl = recordTTL
			}
		}
		if kind == 1 || kind == 28 {
			if (kind == 1 && size != 4) || (kind == 28 && size != 16) {
				return 0, errors.New("DNS address length")
			}
			address, ok := netip.AddrFromSlice(reply[offset : offset+size])
			if !ok || !address.IsGlobalUnicast() || address.IsPrivate() || address.IsLoopback() || address.IsLinkLocalUnicast() {
				return 0, errors.New("DNS non-public address")
			}
		}
		offset += size
	}
	if offset != len(reply) {
		return 0, errors.New("DNS trailing bytes")
	}
	if reply[3]&15 != 0 || binary.BigEndian.Uint16(reply[6:8]) == 0 {
		ttl = 5
	}
	return ttl, nil
}
