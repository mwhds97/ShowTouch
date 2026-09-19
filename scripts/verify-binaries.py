#!/usr/bin/env python3
"""Check the actual staged/re-extracted executables before distributing a release."""
import hashlib
import plistlib
import struct
import sys
from pathlib import Path

ARM64 = 0x0100000C


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_signature(data, offset, size):
    signature = data[offset:offset + size]
    magic, length, count = struct.unpack_from(">III", signature)
    require(magic == 0xFADE0CC0 and length <= size, "invalid signature blob")
    directories = 0
    for i in range(count):
        kind, start = struct.unpack_from(">II", signature, 12 + 8 * i)
        if kind != 0 and not 0x1000 <= kind <= 0x1005:
            continue
        cd = signature[start:]
        header = struct.unpack_from(">9I4BI", cd)
        magic, cd_length, _, _, hash_offset, _, _, slots, limit = header[:9]
        hash_size, hash_type, _, page_shift = header[9:13]
        require(magic == 0xFADE0C02 and cd_length <= len(cd), "invalid CodeDirectory")
        require(hash_type in (1, 2, 3), "unsupported code-signature hash")
        require(limit == offset and page_shift > 0, "signature does not cover executable")
        page_size = 1 << page_shift
        require(slots == (limit + page_size - 1) // page_size, "wrong code-slot count")
        for slot in range(slots):
            page = data[slot * page_size:min((slot + 1) * page_size, limit)]
            digest = (hashlib.sha1(page) if hash_type == 1 else hashlib.sha256(page)).digest()
            begin = hash_offset + slot * hash_size
            require(cd[begin:begin + hash_size] == digest[:hash_size], "code-signature page hash mismatch")
        directories += 1
    require(directories > 0, "missing CodeDirectory")


def check_macho(path, principal=None):
    data = path.read_bytes()
    magic, count = struct.unpack_from(">II", data)
    require(magic == 0xCAFEBABE and count == 2, f"{path.name}: expected a two-slice universal binary")
    found = set()
    arm64e_abi = None
    previous_end = 8 + 20 * count
    for i in range(count):
        cpu, subtype, offset, size, alignment = struct.unpack_from(">5I", data, 8 + 20 * i)
        arch = subtype & 0x00FFFFFF
        require(cpu == ARM64 and arch in (0, 2) and arch not in found, "invalid or duplicate architecture")
        require(offset >= previous_end and offset + size <= len(data), "invalid slice bounds")
        require(offset % (1 << alignment) == 0, "unaligned slice")
        previous_end = offset + size
        found.add(arch)
        if arch == 2:
            arm64e_abi = subtype
        blob = data[offset:offset + size]
        mh, inner_cpu, inner_subtype, filetype, ncmds, cmdsize, _, _ = struct.unpack_from("<8I", blob)
        require((mh, inner_cpu, inner_subtype) == (0xFEEDFACF, cpu, subtype), "fat/inner architecture mismatch")
        require(filetype in (6, 8), "not a dylib or bundle")
        pos = 32
        minimum = None
        signature = None
        dependencies = []
        symtab = None
        for _ in range(ncmds):
            command, length = struct.unpack_from("<II", blob, pos)
            require(length >= 8 and pos + length <= 32 + cmdsize, "invalid load command")
            if command == 0x25:  # LC_VERSION_MIN_IPHONEOS
                minimum = struct.unpack_from("<I", blob, pos + 8)[0]
            elif command == 0x32:  # LC_BUILD_VERSION
                platform, minimum = struct.unpack_from("<II", blob, pos + 8)
                require(platform == 2, "not an iOS executable")
            elif command == 0x1D:  # LC_CODE_SIGNATURE
                signature = struct.unpack_from("<II", blob, pos + 8)
            elif command == 0x2:
                symtab = struct.unpack_from("<4I", blob, pos + 8)
            elif command in (0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023):
                name_offset = struct.unpack_from("<I", blob, pos + 8)[0]
                dependencies.append(blob[pos + name_offset:pos + length].split(b"\0", 1)[0].decode())
            pos += length
        require(pos == 32 + cmdsize and minimum == 0x000E0000, "unexpected deployment target")
        require(signature is not None, "missing code signature")
        check_signature(blob, *signature)
        require(not any("orion" in d.lower() for d in dependencies), "unexpected Orion dependency")
        require(not any("swift" in d.lower() for d in dependencies), "unexpected Swift dependency")
        if principal:
            require(symtab is not None, "missing principal-class symbol table")
            symbol_offset, symbol_count, strings_offset, strings_size = symtab
            strings = blob[strings_offset:strings_offset + strings_size]
            expected = ("_OBJC_CLASS_$_" + principal).encode()
            exported = False
            for index in range(symbol_count):
                name, kind, section, _, value = struct.unpack_from("<IBBHQ", blob, symbol_offset + 16 * index)
                if kind & 1 and section and value and strings[name:].split(b"\0", 1)[0] == expected:
                    exported = True
                    break
            require(exported, "principal Objective-C class is not defined/exported")
        abi = "arm64" if arch == 0 else f"arm64e (subtype 0x{subtype:08x})"
        print(f"PASS {path.name}: {abi}, iOS 14.0, signature hashes verified")
    require(found == {0, 2}, "missing arm64 or arm64e")
    return arm64e_abi


def main(root):
    runtime = root / "Library/MobileSubstrate/DynamicLibraries/ShowTouch.dylib"
    arm64e_abi = check_macho(runtime)
    for directory, executable, principal in [
        ("Library/PreferenceBundles/showtouch.bundle", "showtouch", "P9ShowTouchRootListController"),
        ("Library/ControlCenter/Bundles/CCToggle.bundle", "CCToggle", "P9ShowTouchControlCenterToggle"),
    ]:
        bundle = root / directory
        with (bundle / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
        require(info["CFBundleExecutable"] == executable, "incorrect bundle executable")
        require(info["NSPrincipalClass"] == principal, "incorrect principal class")
        require(info["MinimumOSVersion"] == "14.0", "incorrect bundle minimum OS")
        require(info["CFBundleShortVersionString"] == "0.3.7", "incorrect bundle version")
        require(check_macho(bundle / executable, principal=principal) == arm64e_abi,
                "inconsistent arm64e ABI flags; check embedded compatibility archives")
    with (root / "Library/PreferenceLoader/Preferences/showtouch.plist").open("rb") as file:
        entry = plistlib.load(file)["entry"]
    require(entry["bundle"] == "showtouch" and entry["detail"] == "P9ShowTouchRootListController", "incorrect PreferenceLoader entry")
    with (root / "Library/PreferenceBundles/showtouch.bundle/Root.plist").open("rb") as file:
        items = plistlib.load(file)["items"]
    defaults = {
        "isEnabled": True, "radius": 20, "color": "AA0000FF", "offset": [0, -10],
        "isBordered": False, "borderColor": "000000FF", "borderWidth": 1,
        "isDropShadow": True, "shadowColor": "000000FF", "shadowRadius": 3,
        "shadowOffset": [0, 0], "isShowLocation": False, "displayMode": 0,
        "showRendererSource": False,
    }
    controls = [item for item in items if "key" in item]
    require(len(controls) == 14, "incorrect number of preference controls")
    require({item["key"]: item["default"] for item in controls} == defaults, "preference defaults changed")
    require(all(item["id"] == item["key"] for item in controls), "invalid preference IDs")
    print("PASS: 13 original controls/defaults and optional renderer diagnostics; exported native classes; no Swift or Orion")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: verify-binaries.py STAGING_OR_EXTRACTED_PACKAGE_DIRECTORY")
    try:
        main(Path(sys.argv[1]))
    except (ValueError, OSError, KeyError, struct.error) as error:
        sys.exit(f"ShowTouch package validation failed: {error}")
