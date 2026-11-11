#pragma once
#include "RentalData.h"
#include <map>
#include <stdexcept>

namespace NestGRental {
// Small bounded parser for the fixed runtime protocol. Duplicate object fields,
// floating point numbers and strings with control characters are rejected.
struct Json {
    enum class Type { Null, Object, Array, String, Number, Boolean } type = Type::Null;
    std::string text;
    std::map<std::string, Json> object;
    std::vector<Json> array;
    const Json& At(const std::string& name) const {
        if (type != Type::Object) throw std::runtime_error("json_type");
        return object.at(name);
    }
    std::string String() const {
        if (type != Type::String) throw std::runtime_error("json_type"); return text;
    }
    uint64_t Number() const {
        uint64_t value = 0;
        if (type != Type::Number || !Decimal(text, value)) throw std::runtime_error("json_number");
        return value;
    }
};
class JsonParser {
    std::string_view text;
    size_t pos = 0;
    size_t nodes = 0;
    void Space() { while (pos < text.size() && (text[pos] == ' ' || text[pos] == '\r' || text[pos] == '\n' || text[pos] == '\t')) ++pos; }
    bool Take(char ch) { Space(); if (pos < text.size() && text[pos] == ch) { ++pos; return true; } return false; }
    [[noreturn]] static void Fail() { throw std::runtime_error("json_invalid"); }
    std::string String() {
        if (!Take('"')) Fail();
        std::string value;
        while (pos < text.size()) {
            char ch = text[pos++];
            if (ch == '"') return value;
            if (ch == '\\') {
                if (pos >= text.size()) Fail(); ch = text[pos++];
                switch (ch) {
                case '"': case '\\': case '/': break;
                case 'u': {
                    if (text.size() - pos < 4 || text.substr(pos, 2) != "00") Fail();
                    unsigned code = 0;
                    for (size_t i = 0; i < 4; ++i) {
                        const char digit = text[pos++]; code <<= 4;
                        if (digit >= '0' && digit <= '9') code += digit - '0';
                        else if (digit >= 'a' && digit <= 'f') code += digit - 'a' + 10;
                        else if (digit >= 'A' && digit <= 'F') code += digit - 'A' + 10;
                        else Fail();
                    }
                    if (code < 32 || code > 127) Fail(); ch = static_cast<char>(code); break;
                }
                default: Fail();
                }
            }
            if (static_cast<unsigned char>(ch) < 32 || value.size() >= 4096) Fail();
            value.push_back(ch);
        }
        Fail();
    }
    Json Value(size_t depth) {
        Space(); if (depth > 12 || ++nodes > 40000 || pos >= text.size()) Fail();
        Json result;
        if (Take('{')) {
            result.type = Json::Type::Object;
            if (Take('}')) return result;
            do {
                const auto key = String(); if (!Take(':')) Fail();
                if (!result.object.emplace(key, Value(depth + 1)).second) Fail();
                if (Take('}')) return result;
            } while (Take(','));
            Fail();
        }
        if (Take('[')) {
            result.type = Json::Type::Array;
            if (Take(']')) return result;
            do {
                result.array.push_back(Value(depth + 1)); if (Take(']')) return result;
            } while (Take(','));
            Fail();
        }
        if (text[pos] == '"') { result.type = Json::Type::String; result.text = String(); return result; }
        const auto start = pos;
        while (pos < text.size() && text[pos] >= '0' && text[pos] <= '9') ++pos;
        if (pos > start) {
            result.type = Json::Type::Number; result.text = std::string(text.substr(start, pos - start));
            if (result.text.size() > 1 && result.text[0] == '0') Fail();
            result.Number(); return result;
        }
        for (const auto literal : {std::string_view("true"), std::string_view("false"), std::string_view("null")}) {
            if (text.substr(pos, literal.size()) == literal) {
                pos += literal.size(); result.type = literal == "null" ? Json::Type::Null : Json::Type::Boolean;
                result.text = std::string(literal); return result;
            }
        }
        Fail();
    }
public:
    explicit JsonParser(std::string_view input) : text(input) {}
    Json Parse() {
        if (text.size() > 4 * 1024 * 1024) Fail();
        if (text.substr(0, 3) == "\xEF\xBB\xBF") pos = 3;
        auto result = Value(0); Space(); if (pos != text.size()) Fail(); return result;
    }
};
}
