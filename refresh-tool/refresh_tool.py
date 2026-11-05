#!/usr/bin/env python3
"""Build a staged Lootified Continued data override from verified inputs.

The tool never fetches or trusts arbitrary web pages. Web data must be supplied as
reviewed JSON, and client data comes from LootifiedData.gameTexts.enUS in the
SavedVariables file produced by /lf collect.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class LuaParseError(ValueError):
    pass


TOKEN = re.compile(
    r"\s+|--[^\n]*|(?P<string>'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*(?:\"))|"
    r"(?P<number>-?\d+(?:\.\d+)?)|(?P<ident>[A-Za-z_][A-Za-z0-9_]*)|(?P<sym>[{}\[\]=,;])"
)


def lua_string(token: str) -> str:
    body = token[1:-1]
    return bytes(body, "utf-8").decode("unicode_escape")


class LuaReader:
    def __init__(self, text: str):
        self.tokens: list[tuple[str, str]] = []
        pos = 0
        while pos < len(text):
            m = TOKEN.match(text, pos)
            if not m:
                raise LuaParseError(f"unsupported Lua near offset {pos}: {text[pos:pos+40]!r}")
            pos = m.end()
            if m.group(0).isspace() or m.group(0).startswith("--"):
                continue
            kind = "string" if m.group("string") else "number" if m.group("number") else "ident" if m.group("ident") else "sym"
            self.tokens.append((kind, m.group(0)))
        self.i = 0

    def peek(self, value: str | None = None) -> bool:
        if self.i >= len(self.tokens):
            return False
        return value is None or self.tokens[self.i][1] == value

    def take(self, value: str | None = None) -> tuple[str, str]:
        if self.i >= len(self.tokens):
            raise LuaParseError("unexpected end of file")
        token = self.tokens[self.i]
        if value is not None and token[1] != value:
            raise LuaParseError(f"expected {value!r}, got {token[1]!r}")
        self.i += 1
        return token

    def value(self) -> Any:
        kind, raw = self.tokens[self.i]
        if raw == "{":
            return self.table()
        self.i += 1
        if kind == "string":
            return lua_string(raw)
        if kind == "number":
            return float(raw) if "." in raw else int(raw)
        if raw == "true":
            return True
        if raw == "false":
            return False
        if raw == "nil":
            return None
        return raw

    def table(self) -> Any:
        self.take("{")
        keyed: dict[Any, Any] = {}
        array: list[Any] = []
        while not self.peek("}"):
            if self.peek("["):
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                keyed[key] = self.value()
            elif self.i + 1 < len(self.tokens) and self.tokens[self.i][0] in {"ident", "string"} and self.tokens[self.i + 1][1] == "=":
                key_token = self.take()
                key = lua_string(key_token[1]) if key_token[0] == "string" else key_token[1]
                self.take("=")
                keyed[key] = self.value()
            else:
                array.append(self.value())
            if self.peek(",") or self.peek(";"):
                self.take()
        self.take("}")
        if keyed and array:
            for index, item in enumerate(array, 1):
                keyed[index] = item
            return keyed
        return keyed if keyed else array


def load_saved_variables(path: Path) -> dict[str, Any]:
    reader = LuaReader(path.read_text(encoding="utf-8-sig"))
    values: dict[str, Any] = {}
    while reader.i < len(reader.tokens):
        kind, name = reader.take()
        if kind != "ident":
            raise LuaParseError(f"expected top-level variable, got {name!r}")
        reader.take("=")
        values[name] = reader.value()
        if reader.peek(";"):
            reader.take()
    return values


def as_int_key_map(value: Any, field: str) -> dict[int, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object keyed by IDs")
    result: dict[int, Any] = {}
    for key, item in value.items():
        try:
            number = int(key)
        except (TypeError, ValueError) as exc:
            raise ValueError(f"{field} contains non-numeric ID {key!r}") from exc
        if number <= 0:
            raise ValueError(f"{field} contains invalid ID {number}")
        result[number] = item
    return result


def lua_key(key: Any) -> str:
    if isinstance(key, int):
        return f"[{key}]"
    if isinstance(key, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        return key
    return "[" + lua_literal(str(key)) + "]"


def lua_literal(value: Any, indent: int = 0) -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        if not value:
            return "{}"
        pad = " " * indent
        child = " " * (indent + 4)
        return "{\n" + ",\n".join(child + lua_literal(v, indent + 4) for v in value) + "\n" + pad + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        pad = " " * indent
        child = " " * (indent + 4)
        parts = [child + lua_key(k) + " = " + lua_literal(v, indent + 4) for k, v in value.items()]
        return "{\n" + ",\n".join(parts) + "\n" + pad + "}"
    raise TypeError(f"cannot serialize {type(value).__name__}")


def client_collect(saved: dict[str, Any]) -> dict[str, Any]:
    root = saved.get("LootifiedData", {})
    game = root.get("gameTexts", {}) if isinstance(root, dict) else {}
    collected = game.get("enUS", {}) if isinstance(game, dict) else {}
    if not isinstance(collected, dict):
        raise ValueError("LootifiedData.gameTexts.enUS was not found in the SavedVariables file")
    return collected


def validate_web(data: dict[str, Any]) -> None:
    if not isinstance(data, dict):
        raise ValueError("web data must be a JSON object")
    if not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", str(data.get("build", ""))):
        raise ValueError("web data needs a build like 1.60.1.70755")
    for field in ("items", "item_stats", "quests", "world_drops"):
        if field in data:
            as_int_key_map(data[field], field)
    for field in ("instances", "dungeon_maps", "bis_weights"):
        if field in data and not isinstance(data[field], (dict, list)):
            raise ValueError(f"{field} must be an object or array")


def build_override(client: dict[str, Any] | None, web: dict[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "format": 1,
        "client": client or {},
        "web": web or {},
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect-file", type=Path, help="LootifiedContinued SavedVariables Lua file after /lf collect")
    parser.add_argument("--web-data", type=Path, help="reviewed Forever data JSON")
    parser.add_argument("--output", type=Path, required=True, help="staged output Lua file")
    args = parser.parse_args()
    if not args.collect_file and not args.web_data:
        parser.error("provide --collect-file and/or --web-data")

    client = None
    if args.collect_file:
        client = client_collect(load_saved_variables(args.collect_file))
    web = None
    if args.web_data:
        web = json.loads(args.web_data.read_text(encoding="utf-8"))
        validate_web(web)

    override = build_override(client, web)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    text = "-- Generated by Lootified Continued Refresh Tool. Review before applying.\n"
    text += "local _, LJ = ...\nLJ.RefreshInput = " + lua_literal(override) + "\n"
    args.output.write_text(text, encoding="utf-8", newline="\n")
    print(f"Wrote staged Lua input: {args.output}")
    if client:
        print("Client collect: loaded English gameTexts data")
    if web:
        print(f"Web data: validated build {web['build']}")
    print("No live addon files were overwritten. Review the staged file before applying it.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, LuaParseError, json.JSONDecodeError) as exc:
        print(f"refresh_tool: error: {exc}", file=sys.stderr)
        raise SystemExit(2)
