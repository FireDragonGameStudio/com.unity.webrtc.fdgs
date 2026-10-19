#!/usr/bin/env python3
"""Checks the classes.jar of libwebrtc.aar against itself and against libwebrtc.a.

Usage: check_android_jar.py [--registration-srcjar <srcjar>] <classes.jar> <symbols file>...

Each symbols file is the `llvm-nm --defined-only -j` output of one libwebrtc.a. The check fails when
- a class in the jar refers to an org.webrtc, org.jni_zero or J class that is not in the jar (the libwebrtc
  dist_jar has direct_deps_only, which leaves out the JNI Zero generated <Class>Jni and J.N classes),
- a Java_J_N_* symbol of a libwebrtc.a is not a native method of J.N (hashed JNI Zero names),
- J.N has a native method that no libwebrtc.a defines, other than EXPECTED_ONLY_IN_JAVA,
- a class file is newer than Java 17 (version 61), which Unity 6 builds with.

--registration-srcjar is the srcjar with J/N.java that the jar was built from; it maps the hashed names to the
Java methods for EXPECTED_ONLY_IN_JAVA and the messages.
"""

import argparse
import os
import re
import struct
import sys
import zipfile

MAX_CLASS_VERSION = 61
CHECKED_PACKAGES = ('org/webrtc/', 'org/jni_zero/', 'J/')
ACC_NATIVE = 0x0100

# Natives of libwebrtc.jar that are implemented in libjingle_peerconnection_so.so of the AAR but not in
# libwebrtc.a (//:webrtc does not depend on their native targets). Calling them through the Unity plugin
# throws UnsatisfiedLinkError, as it did before JNI Zero.
EXPECTED_ONLY_IN_JAVA = {
    'org.webrtc.Dav1dDecoder#createDecoder',  # dav1d_av1_jni
    'org.webrtc.EglBase10Impl#getCurrentNativeEGLContext',  # video_egl_jni
    'org.webrtc.LibaomAv1Encoder#create',  # libaom_av1_encoder_jni (only in libjingle_peerconnection_so)
    'org.webrtc.Metrics#enable',  # libjingle_peerconnection_metrics_default_jni
    'org.webrtc.Metrics#getAndReset',
}


def parse_class(data):
  """Returns (major version, referenced class names, [(method name, access flags)])."""
  magic, _minor, major, count = struct.unpack_from('>IHHH', data, 0)
  if magic != 0xCAFEBABE:
    raise ValueError('not a class file')
  pos = 10
  utf8 = {}
  class_name_indexes = []
  i = 1
  while i < count:
    tag = data[pos]
    pos += 1
    if tag == 1:  # Utf8
      (length,) = struct.unpack_from('>H', data, pos)
      utf8[i] = data[pos + 2:pos + 2 + length].decode('utf-8', 'replace')
      pos += 2 + length
    elif tag == 7:  # Class
      class_name_indexes.append(struct.unpack_from('>H', data, pos)[0])
      pos += 2
    elif tag in (8, 16, 19, 20):  # String, MethodType, Module, Package
      pos += 2
    elif tag == 15:  # MethodHandle
      pos += 3
    elif tag in (3, 4, 9, 10, 11, 12, 17, 18):  # Integer, Float, member refs, NameAndType, (Invoke)Dynamic
      pos += 4
    elif tag in (5, 6):  # Long and Double take two entries
      pos += 8
      i += 1
    else:
      raise ValueError(f'unknown constant pool tag {tag}')
    i += 1
  # access_flags, this_class, super_class, interfaces
  (interfaces,) = struct.unpack_from('>H', data, pos + 6)
  pos += 8 + 2 * interfaces

  def read_members(pos):
    (members,) = struct.unpack_from('>H', data, pos)
    pos += 2
    result = []
    for _ in range(members):
      flags, name_index, _descriptor, attributes = struct.unpack_from('>HHHH', data, pos)
      pos += 8
      for _ in range(attributes):
        (length,) = struct.unpack_from('>I', data, pos + 2)
        pos += 6 + length
      result.append((utf8[name_index], flags))
    return pos, result

  pos, _fields = read_members(pos)
  _pos, methods = read_members(pos)

  names = set()
  for index in class_name_indexes:
    # Array classes: [[Lorg/webrtc/Foo; -> org/webrtc/Foo
    name = utf8[index].lstrip('[')
    if name.startswith('L') and name.endswith(';'):
      name = name[1:-1]
    names.add(name)
  return major, names, methods


def jni_mangle(name):
  """The JNI short name mangling of a class or method name."""
  out = []
  for c in name:
    if c.isascii() and c.isalnum():
      out.append(c)
    elif c == '/':
      out.append('_')
    elif c == '_':
      out.append('_1')
    elif c == ';':
      out.append('_2')
    elif c == '[':
      out.append('_3')
    else:
      out.append(f'_0{ord(c):04x}')
  return ''.join(out)


def read_original_names(srcjar):
  """Maps Java_J_N_* names to the Java methods, from the '// Original name:' comments of J/N.java."""
  with zipfile.ZipFile(srcjar) as f:
    source = f.read('J/N.java').decode()
  pairs = re.findall(r'// Original name: (\S+)\n\s*public static native \S+ ([\w$]+)\(', source)
  return {'Java_J_N_' + jni_mangle(method): original for original, method in pairs}


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--registration-srcjar')
  parser.add_argument('jar')
  parser.add_argument('symbols', nargs='+')
  args = parser.parse_args()

  failed = False
  classes = {}
  with zipfile.ZipFile(args.jar) as jar:
    for entry in jar.namelist():
      if entry.endswith('.class'):
        classes[entry[:-len('.class')]] = parse_class(jar.read(entry))
  print(f'{args.jar}: {len(classes)} classes')

  versions = {}
  for name, (major, _refs, _methods) in classes.items():
    versions.setdefault(major, []).append(name)
  print('Class file versions: ' + ', '.join(f'{v} ({len(n)} classes)' for v, n in sorted(versions.items())))
  too_new = sorted(n for v, names in versions.items() if v > MAX_CLASS_VERSION for n in names)
  if too_new:
    failed = True
    print(f'ERROR: {len(too_new)} class files are newer than Java 17 (version {MAX_CLASS_VERSION}): '
          f'{", ".join(too_new[:5])}')

  packages = sorted({n.rsplit('/', 1)[0] if '/' in n else '' for n in classes})
  print('Packages: ' + ', '.join(packages))
  jni_classes = [n for n in classes if n.endswith('Jni')]
  print(f'{len(jni_classes)} JNI Zero <Class>Jni classes')

  missing = {}
  for name, (_major, refs, _methods) in classes.items():
    for ref in refs:
      if ref.startswith(CHECKED_PACKAGES) and ref not in classes:
        missing.setdefault(ref, []).append(name)
  if missing:
    failed = True
    print(f'ERROR: {len(missing)} classes are used but not in the jar:')
    for ref, users in sorted(missing.items()):
      print(f'  {ref} (used by {", ".join(sorted(users)[:3])}{", ..." if len(users) > 3 else ""})')

  natives = set()
  if 'J/N' in classes:
    natives = {'Java_J_N_' + jni_mangle(m) for m, flags in classes['J/N'][2] if flags & ACC_NATIVE}
    print(f'J.N: {len(natives)} native methods')
  else:
    failed = True
    print('ERROR: the jar has no J.N class')
  original_names = {}
  if args.registration_srcjar and os.path.exists(args.registration_srcjar):
    original_names = read_original_names(args.registration_srcjar)
  elif args.registration_srcjar:
    print(f'WARNING: {args.registration_srcjar} does not exist; Java method names unknown')

  def describe(names, limit=20):
    names = sorted(names)
    text = ', '.join(f'{n} ({original_names.get(n, "?")})' for n in names[:limit])
    return text + (f' and {len(names) - limit} more' if len(names) > limit else '')

  for path in args.symbols:
    with open(path) as f:
      symbols = {line.strip() for line in f if line.startswith('Java_J_N_')}
    print(f'{path}: {len(symbols)} Java_J_N_ symbols')
    if not symbols:
      failed = True
      print(f'ERROR: {path} has no Java_J_N_ symbols')
    if symbols - natives:
      failed = True
      print(f'ERROR: {len(symbols - natives)} symbols are not native methods of J.N: '
            f'{describe(symbols - natives)}')
    only_java = natives - symbols
    unexpected = {n for n in only_java if original_names.get(n) not in EXPECTED_ONLY_IN_JAVA}
    if only_java - unexpected:
      print(f'Native methods of J.N not in libwebrtc.a, as expected: {describe(only_java - unexpected)}')
    if unexpected:
      failed = True
      print(f'ERROR: {len(unexpected)} native methods of J.N are not in libwebrtc.a: {describe(unexpected)}')

  if failed:
    sys.exit(1)
  print('classes.jar check passed')


if __name__ == '__main__':
  main()
