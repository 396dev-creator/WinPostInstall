#!/usr/bin/env python3
"""Verify the base64(UTF-16LE) algorithm used in lib.rs (encode_ps_command)
and tauri-bridge.ts (encodePsCommand) matches PowerShell's -EncodedCommand format.

The Rust/TS implementations use this exact chunked algorithm; here we port it
line-by-line and compare against Python's reference base64 library output.
"""
import base64
import string

B64 = (string.ascii_uppercase + string.ascii_lowercase + string.digits + "+/").encode()

def to_utf16_units(s: str):
    """Simulate JS charCodeAt / Rust encode_utf16: produce UTF-16 code units
    including surrogate pairs for astral chars (emoji etc.)."""
    units = []
    for c in s:
        cp = ord(c)
        if cp > 0xFFFF:
            cp -= 0x10000
            units.append(0xD800 + (cp >> 10))
            units.append(0xDC00 + (cp & 0x3FF))
        else:
            units.append(cp)
    return units

def encode_ps_command_port(script: str) -> str:
    """Line-by-line port of the Rust fn encode_ps_command / TS encodePsCommand."""
    utf16 = to_utf16_units(script)                 # Vec<u16> (JS charCodeAt / Rust encode_utf16)
    bytes_ = bytearray()
    for w in utf16:                                # w.to_le_bytes()
        bytes_ += w.to_bytes(2, "little")
    out = []
    for chunk in chunks(bytes_, 3):                # bytes.chunks(3)
        b0 = chunk[0]
        b1 = chunk[1] if len(chunk) > 1 else 0
        b2 = chunk[2] if len(chunk) > 2 else 0
        n = (b0 << 16) | (b1 << 8) | b2
        out.append(chr(B64[(n >> 18) & 63]))
        out.append(chr(B64[(n >> 12) & 63]))
        out.append(chr(B64[(n >> 6) & 63]) if len(chunk) > 1 else "=")
        out.append(chr(B64[n & 63]) if len(chunk) > 2 else "=")
    return "".join(out)

def chunks(data, n):
    for i in range(0, len(data), n):
        yield data[i:i+n]

def reference(script: str) -> str:
    """PowerShell -EncodedCommand reference: Base64(UTF-16LE bytes)."""
    return base64.b64encode(script.encode("utf-16-le")).decode()

cases = [
    "",
    "Write-Output 'Hello World'",
    "Enable-ComputerRestore -Drive 'C:\\' -ErrorAction SilentlyContinue",
    "& 'C:\\Program Files\\WinPostInstall\\WinPostInstall.ps1' -ConfigFile 'C:\\Temp\\cfg.json' -Silent",
    'Multi\nline\r\nscript with "double quotes" and & pipes | and $vars',
    "try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }",
    "Unicode: é中文\U0001F600 emoji",
]

all_ok = True
for c in cases:
    port, ref = encode_ps_command_port(c), reference(c)
    ok = port == ref
    all_ok &= ok
    print(f"{'PASS' if ok else 'FAIL'} | len={len(c):>4} | {c[:60]!r}")
    if not ok:
        print(f"  port: {port}")
        print(f"  ref : {ref}")

# Length edge cases: base64 padding for byte lengths mod 3 == 1 and 2
edge = ["a", "ab", "abc", "abcd"]
for c in edge:
    assert encode_ps_command_port(c) == reference(c), f"edge fail: {c!r}"
print("Edge-case padding (1,2,3,4 bytes): PASS")

# Surrogate pair handling (JS charCodeAt path): emoji = 2 UTF-16 code units
emoji = "\U0001F600"
assert encode_ps_command_port(emoji) == reference(emoji)
print("Surrogate pair (emoji) UTF-16LE encoding: PASS")

print("\nALL PASS — algorithm is correct for PowerShell -EncodedCommand" if all_ok else "\nMISMATCH FOUND!")
