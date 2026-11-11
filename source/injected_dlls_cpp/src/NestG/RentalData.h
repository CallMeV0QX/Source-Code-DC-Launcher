#pragma once

// Rental inputs are data. They are never evaluated by the unrestricted retail
// Lua VM; consequently switching accounts can revoke every rental contribution
// by dropping one immutable snapshot, without undoing Lua side effects.
#include <algorithm>
#include <charconv>
#include <cctype>
#include <cstdint>
#include <limits>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace NestGRental {
struct Manifest { uint64_t gid = 0; uint64_t size = 0; };
struct Data {
    std::map<uint32_t, std::string> depotKeys;
    std::map<uint32_t, uint64_t> accessTokens;
    std::map<uint32_t, uint64_t> statIds;
    std::map<uint32_t, Manifest> manifests;
    std::vector<uint32_t> pinned;
};

inline bool Decimal(std::string_view text, uint64_t& value) {
    if (text.empty() || text.size() > 20 ||
        text.find_first_not_of("0123456789") != std::string_view::npos) return false;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
    return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
}

class DataParser {
    std::string_view input;
    size_t pos = 0;
    bool invalid = false;
    void Space() {
        for (;;) {
            while (pos < input.size() && std::isspace(static_cast<unsigned char>(input[pos]))) ++pos;
            if (input.substr(pos, 2) != "--") return;
            pos += 2;
            if (input.substr(pos, 2) == "[[") {
                const auto end = input.find("]]", pos + 2);
                if (end == std::string_view::npos) { invalid = true; return; }
                pos = end + 2;
            } else {
                const auto end = input.find('\n', pos);
                pos = end == std::string_view::npos ? input.size() : end + 1;
            }
        }
    }
    bool Take(char ch) { Space(); if (invalid || pos >= input.size() || input[pos] != ch) return false; ++pos; return true; }
    bool Literal(std::string& value) {
        Space(); value.clear(); if (invalid || pos >= input.size()) return false;
        const char first = input[pos];
        if (first == '\'' || first == '"') {
            ++pos;
            while (pos < input.size()) {
                const char ch = input[pos++];
                if (ch == first) return true;
                if (ch == '\\' || ch == '\r' || ch == '\n' || static_cast<unsigned char>(ch) < 32) return false;
                value.push_back(ch);
                if (value.size() > 128) return false;
            }
            return false;
        }
        while (pos < input.size() && input[pos] >= '0' && input[pos] <= '9') value.push_back(input[pos++]);
        return !value.empty() && value.size() <= 20;
    }
public:
    explicit DataParser(std::string_view value) : input(value) {}
    bool Parse(Data& output) {
        if (input.size() > 1024 * 1024 || input.find('\0') != std::string_view::npos) return false;
        Data candidate;
        size_t calls = 0;
        for (;;) {
            Space(); if (invalid) return false;
            if (pos == input.size()) { output = std::move(candidate); return calls > 0; }
            const auto begin = pos;
            while (pos < input.size() && std::isalpha(static_cast<unsigned char>(input[pos]))) ++pos;
            if (begin == pos || pos - begin > 24 || ++calls > 8192) return false;
            std::string name(input.substr(begin, pos - begin));
            std::transform(name.begin(), name.end(), name.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
            if (!Take('(')) return false;
            std::vector<std::string> args(1);
            if (!Literal(args[0])) return false;
            while (Take(',')) { if (args.size() >= 3) return false; args.emplace_back(); if (!Literal(args.back())) return false; }
            if (!Take(')')) return false;
            Take(';');
            uint64_t first = 0, second = 0;
            if (!Decimal(args[0], first) || first == 0 || first > UINT32_MAX) return false;
            const auto id = static_cast<uint32_t>(first);
            if (name == "addappid") {
                if (args.size() > 1 && !Decimal(args[1], second)) return false;
                std::string key;
                if (args.size() == 3) {
                    key = args[2];
                    if (key.size() != 64 || key.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos) return false;
                }
                auto [it, added] = candidate.depotKeys.emplace(id, key);
                if (!added && !key.empty()) {
                    if (!it->second.empty() && it->second != key) return false;
                    it->second = key;
                }
            } else if (name == "addtoken" || name == "setstat" || name == "setmanifestid") {
                if (args.size() < 2 || args.size() > (name == "setmanifestid" ? 3u : 2u) ||
                    !Decimal(args[1], second) || second == 0) return false;
                if (name == "addtoken") candidate.accessTokens[id] = second;
                else if (name == "setstat") candidate.statIds[id] = second;
                else {
                    uint64_t ignored = 0;
                    if (args.size() == 3 && !Decimal(args[2], ignored)) return false;
                    candidate.manifests[id] = { second, 0 };
                }
            } else if (name == "pinapp" && args.size() == 1) candidate.pinned.push_back(id);
            else return false; // No arbitrary Lua, HTTP, credential writes or globals.
        }
    }
};

inline bool Merge(Data& target, const Data& source) {
    for (const auto& [id, key] : source.depotKeys) {
        auto it = target.depotKeys.find(id);
        if (it != target.depotKeys.end() && !key.empty() && !it->second.empty() && it->second != key) return false;
    }
    for (const auto& [id, manifest] : source.manifests) {
        auto it = target.manifests.find(id);
        if (it != target.manifests.end() && it->second.gid != manifest.gid) return false;
    }
    for (const auto& [id, key] : source.depotKeys) if (!key.empty() || !target.depotKeys.count(id)) target.depotKeys[id] = key;
    target.accessTokens.insert(source.accessTokens.begin(), source.accessTokens.end());
    target.statIds.insert(source.statIds.begin(), source.statIds.end());
    target.manifests.insert(source.manifests.begin(), source.manifests.end());
    target.pinned.insert(target.pinned.end(), source.pinned.begin(), source.pinned.end());
    return true;
}
}
