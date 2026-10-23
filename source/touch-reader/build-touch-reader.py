#!/usr/bin/env python3
"""Build the tiny project input helper with existing Apple clang; no install."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess

base = Path(__file__).resolve().parent
obj = base/'touch-reader.o'
subprocess.run(['/Library/Developer/CommandLineTools/usr/bin/clang',
                '-target','armv7-linux-gnueabi','-march=armv7-a','-marm',
                '-c',str(base/'touch-reader.S'),'-o',str(obj)],check=True)
data = obj.read_bytes()
assert data[:6] == b'\x7fELF\x01\x01'
header = struct.unpack_from('<16sHHIIIIIHHHHHH',data)
assert header[2] == 40
shoff, shsize, shnum, string_index = header[6], header[11], header[12], header[13]
sections = [struct.unpack_from('<IIIIIIIIII',data,shoff+i*shsize) for i in range(shnum)]
names_section = sections[string_index]
names = data[names_section[4]:names_section[4]+names_section[5]]
def name(section):
    return names[section[0]:].split(b'\0',1)[0].decode()
text_index = next(i for i,s in enumerate(sections) if name(s)=='.text')
text_section = sections[text_index]
code = bytearray(data[text_section[4]:text_section[4]+text_section[5]])
for section in sections:
    if section[1] not in (4,9) or section[7] != text_index:
        continue
    assert section[1] == 9, 'Only ARM REL relocations are expected'
    symbols = sections[section[6]]
    for offset in range(section[4],section[4]+section[5],8):
        location, info = struct.unpack_from('<II',data,offset)
        kind, symbol_index = info & 255, info >> 8
        symbol = struct.unpack_from('<IIIBBH',data,symbols[4]+symbol_index*symbols[9])
        assert kind == 28 and symbol[5] == text_index, 'Only local ARM calls are allowed'
        instruction = struct.unpack_from('<I',code,location)[0]
        addend = instruction & 0xffffff
        if addend & 0x800000:
            addend -= 0x1000000
        displacement = symbol[1] + addend*4 - location
        assert displacement % 4 == 0 and -(1<<25) <= displacement < (1<<25)
        struct.pack_into('<I',code,location,(instruction & 0xff000000) | ((displacement >> 2) & 0xffffff))
assert len(code)<4096
ident = b'\x7fELF\x01\x01\x01'+b'\0'*9
size = 4096+len(code)
elf_header = struct.pack('<16sHHIIIIIHHHHHH',ident,2,40,1,0x11000,52,0,0x05000000,52,32,2,0,0,0)
load = struct.pack('<IIIIIIII',1,0,0x10000,0x10000,size,size,5,4096)
stack = struct.pack('<IIIIIIII',0x6474e551,0,0,0,0,0,6,16)
binary = (elf_header+load+stack).ljust(4096,b'\0')+bytes(code)
out = base/'touch-reader'
out.write_bytes(binary)
out.chmod(0o755)
manifest = {'source':'touch-reader.S','source_sha256':hashlib.sha256((base/'touch-reader.S').read_bytes()).hexdigest(),
            'binary_sha256':hashlib.sha256(binary).hexdigest(),'bytes':len(binary),
            'architecture':'ARMv7 EABI5 static','external_libraries':[],
            'capabilities':['open /dev/input/event8 read-only','EVIOCGRAB','read events','write event metadata to stdout'],
            'network_calls':False,'text_segment_writable':False,'executable_stack':False}
(base/'touch-reader-build.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
