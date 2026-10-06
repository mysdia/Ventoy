#!/usr/bin/env python3
"""Real VLNK fixtures; ordinary text targets, NOT a disk-image boot test.

Layout: include/grub/ventoy.h ventoy_vlnk; CRC: Vlnk/src/crc32.c.
The unterminated fixture has a valid CRC and must fail path validation.
"""
import pathlib
import struct
import sys

GUID = struct.pack('<IHH8s', 0x77772020, 0x2e77, 0x6576, b'ntoy.net')
OFFSET = 2048 * 512
ESP_SIG = 0x13572468
DATA_SIG = 0x24681357


def crc32c(data):
    crc = 0xffffffff
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82f63b78 if crc & 1 else 0)
    return crc ^ 0xffffffff


def link(signature, path, bad_crc=False):
    assert len(path) <= 384
    header = bytearray(struct.pack('<16sIIQ384s96s', GUID, 0, signature,
                                   OFFSET, path, bytes(96)))
    struct.pack_into('<I', header, 16, crc32c(header) ^ int(bad_crc))
    return bytes(header) + bytes(32768 - len(header))


def prepare(stage, data):
    (stage / 'vlnk/direct').mkdir(parents=True)
    data.mkdir(parents=True)
    for name, directory in (('same', stage), ('second', data)):
        text = f'echo "[ESP-TEST] VLNK_CONTENT_{name}"\n'.encode()
        (directory / f'{name}-target.txt').write_bytes(text + b'# padding\n' * 4096)
        signature = ESP_SIG if name == 'same' else DATA_SIG
        (stage / f'vlnk/direct/{name}.vlnk.img').write_bytes(
            link(signature, f'/{name}-target.txt'.encode()))
    for name, path, corrupt in (
        ('bad-crc', b'/same-target.txt', True),
        ('missing', b'/no-such-target.txt', False),
        ('unterminated', b'/' + b'x' * 383, False),
    ):
        (stage / f'vlnk/direct/{name}.vlnk.img').write_bytes(link(ESP_SIG, path, corrupt))


def probes(part):
    lines = []
    # Before any scan: exercise the on-demand parser, not the cached mapping.
    for name, disk in (('same', f'hd0,{part}'), ('second', 'hd1,1')):
        lines += [f'set esp_dst=stale',
                  f'if vt_get_vlnk_dst "$vtoy_iso_part/vlnk/direct/{name}.vlnk.img" esp_dst; then',
                  f'    if [ "$esp_dst" = "({disk})/{name}-target.txt" ]; then',
                  f'        echo "[ESP-TEST] VLNK_PARSE_{name}"',
                  '    fi', 'fi']
    for name in ('bad-crc', 'missing', 'unterminated'):
        lines += [f'echo "[ESP-TEST] VLNK_BEGIN_{name}"',
                  'set esp_dst=stale',
                  f'if vt_get_vlnk_dst "$vtoy_iso_part/vlnk/direct/{name}.vlnk.img" esp_dst; then',
                  f'    echo "[ESP-TEST] FAIL_ACCEPTED_{name}"',
                  'else', '    if [ -z "$esp_dst" ]; then',
                  f'        echo "[ESP-TEST] VLNK_REJECT_{name}"',
                  '    fi', 'fi']
    for name in ('same', 'second'):
        # source uses grub_file_open on the ORIGINAL link and executes target text.
        lines += [f'source "$vtoy_iso_part/vlnk/direct/{name}.vlnk.img"']
    return '\n'.join(lines) + '\n'


def check(log):
    text = log.read_text(errors='replace')
    for name in ('same', 'second'):
        for kind in ('PARSE', 'CONTENT'):
            assert f'[ESP-TEST] VLNK_{kind}_{name}' in text, (kind, name)
    for name in ('bad-crc', 'missing', 'unterminated'):
        start = text.index(f'[ESP-TEST] VLNK_BEGIN_{name}')
        end = text.index(f'[ESP-TEST] VLNK_REJECT_{name}', start)
        diagnostic = {'bad-crc': 'VLNK invalid crc',
                      'missing': 'File Find: [ NO ]',
                      'unterminated': 'VLNK invalid file path'}[name]
        assert diagnostic in text[start:end], name
    assert '[ESP-TEST] FAIL_' not in text


if __name__ == '__main__':
    assert crc32c(b'123456789') == 0xe3069283
    command, *args = sys.argv[1:]
    if command == 'prepare':
        prepare(*map(pathlib.Path, args))
    elif command == 'signature':
        disk, kind = args
        with open(disk, 'r+b') as stream:
            stream.seek(0x1b8)
            stream.write(struct.pack('<I', ESP_SIG if kind == 'esp' else DATA_SIG))
    elif command == 'probes':
        print(probes(int(args[0])), end='')
    elif command == 'check':
        check(pathlib.Path(args[0]))
    else:
        raise ValueError(command)
