#!/usr/bin/env python3
"""Build the native libraries and copy them into the Godot project.

With no options, build the library for this computer. Use --package to build
the library that a desktop package needs on this platform: a universal library
on macOS, and the library of this architecture (x86_64 or arm64) on Windows
and Linux. Use --android to cross-compile the libraries of the Android package
(arm64, and x86_64 for emulators) with the Android NDK.

The audio library loads FluidSynth at run time. This also builds the FluidSynth
shared library (tools/build_fluidsynth.py, which needs CMake). Without it, no
MIDI music plays.
"""
import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

import build_fluidsynth

ROOT = Path(__file__).resolve().parents[1]
# one Cargo workspace holds every crate, so they share dependencies and build in parallel
WORKSPACE = ROOT / 'native'
TARGET = WORKSPACE / 'target'
MODULES = ('simulation', 'rendering', 'formats', 'audio', 'scripting')
MACOS_TARGETS = ('aarch64-apple-darwin', 'x86_64-apple-darwin')
# the Windows and Linux folders that desktop packages include, and their Rust targets.
# An explicit target stops an emulated x86_64 toolchain from building the wrong library
PACKAGE_TARGETS = {
    'linux-x86_64': 'x86_64-unknown-linux-gnu',
    'linux-arm64': 'aarch64-unknown-linux-gnu',
    'windows-x86_64': 'x86_64-pc-windows-msvc',
    'windows-arm64': 'aarch64-pc-windows-msvc',
}
# the Android folders and their Rust targets. The Android package holds both, so it
# also runs without translation on x86_64 emulators. API 24 is the oldest Android
# version that Godot 4 supports
ANDROID_TARGETS = {
    'android-arm64': 'aarch64-linux-android',
    'android-x86_64': 'x86_64-linux-android',
}
ANDROID_API = 24


def host_folder():
    machine = platform.machine().lower()
    arch = 'arm64' if machine in ('arm64', 'aarch64') else 'x86_64'
    if sys.platform == 'darwin':
        return 'macos'
    if sys.platform == 'win32':
        return f'windows-{arch}'
    return f'linux-{arch}'


def library_name(module):
    name = f'opensc2k_{module}'
    if sys.platform == 'darwin':
        return f'lib{name}.dylib'
    if sys.platform == 'win32':
        return f'{name}.dll'
    return f'lib{name}.so'


def _cargo(arguments, quiet, packages=None, environment=None):
    if shutil.which('cargo') is None:
        raise OSError('cargo is required to build the native libraries (https://rustup.rs)')
    selection = [f'--package=opensc2k_{module}' for module in packages] if packages else ['--workspace']
    command = ['cargo', *arguments, *selection]
    if quiet:
        command.append('--quiet')
    subprocess.run(command, cwd=WORKSPACE, check=True, env=environment)


def _add_targets(triples):
    subprocess.run(['rustup', 'target', 'add', *triples], cwd=WORKSPACE, check=True)


def _install(built, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.read_bytes() != built.read_bytes():
        # Replace the file instead of writing over it. macOS stops new processes
        # that load a signed library whose file changed while it was mapped.
        staged = target.with_name(target.name + '.new')
        shutil.copy2(built, staged)
        os.replace(staged, target)
    return target


def build(profile='release', quiet=False):
    """Build the host libraries. Cargo skips unchanged sources."""
    _cargo(['build', *(['--release'] if profile == 'release' else [])], quiet)
    targets = []
    for module in MODULES:
        built = TARGET / profile / library_name(module)
        target = ROOT / 'game/bin' / f'opensc2k_{module}' / host_folder() / library_name(module)
        targets.append(_install(built, target))
    return targets + build_fluidsynth.build(quiet=quiet)


def build_package(quiet=False):
    """Build the release libraries of a desktop package for this platform."""
    if sys.platform == 'darwin':
        # one Cargo call builds both architectures, so they also build in parallel
        _add_targets(MACOS_TARGETS)
        _cargo(['build', '--release', *(f'--target={triple}' for triple in MACOS_TARGETS)], quiet)
        targets = []
        for module in MODULES:
            slices = [str(TARGET / triple / 'release' / library_name(module)) for triple in MACOS_TARGETS]
            universal = TARGET / 'universal' / library_name(module)
            universal.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['lipo', '-create', *slices, '-output', str(universal)], check=True)
            targets.append(_install(universal, ROOT / 'game/bin' / f'opensc2k_{module}' / 'macos' / library_name(module)))
        return targets + build_fluidsynth.build(quiet=quiet)
    if host_folder() not in PACKAGE_TARGETS:
        raise OSError(f'desktop packages do not include {host_folder()}')
    triple = PACKAGE_TARGETS[host_folder()]
    _add_targets([triple])
    _cargo(['build', '--release', '--target', triple], quiet)
    targets = []
    for module in MODULES:
        built = TARGET / triple / 'release' / library_name(module)
        targets.append(_install(built, ROOT / 'game/bin' / f'opensc2k_{module}' / host_folder() / library_name(module)))
    return targets + build_fluidsynth.build(quiet=quiet)


def android_ndk():
    """The Android NDK folder: ANDROID_NDK_HOME or ANDROID_NDK_ROOT, else the newest NDK of the SDK."""
    for variable in ('ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT'):
        if os.environ.get(variable):
            return Path(os.environ[variable])
    for variable in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        folder = Path(os.environ.get(variable, '')) / 'ndk'
        if os.environ.get(variable) and folder.is_dir():
            versions = sorted(folder.iterdir(), key=lambda path: [int(part) for part in path.name.split('.')
                                                                  if part.isdigit()])
            if versions:
                return versions[-1]
    raise OSError('set ANDROID_NDK_HOME to the Android NDK to build the Android libraries')


def android_toolchain(triple):
    """The NDK folder, and the NDK clang and llvm-ar of an Android Rust target."""
    ndk = android_ndk()
    host = 'darwin-x86_64' if sys.platform == 'darwin' else 'windows-x86_64' if sys.platform == 'win32' \
        else 'linux-x86_64'
    tools = ndk / 'toolchains' / 'llvm' / 'prebuilt' / host / 'bin'
    suffix = '.cmd' if sys.platform == 'win32' else ''
    clang = tools / f'{triple}{ANDROID_API}-clang{suffix}'
    if not clang.is_file():
        raise OSError(f'{clang} is missing; ANDROID_NDK_HOME must name an NDK of version 23 or later')
    return ndk, clang, tools / f'llvm-ar{".exe" if sys.platform == "win32" else ""}'


def build_android(quiet=False):
    """Cross-compile the release libraries of the Android package with the NDK."""
    triples = list(ANDROID_TARGETS.values())
    _add_targets(triples)
    environment = dict(os.environ)
    for triple in triples:
        _, clang, archiver = android_toolchain(triple)
        variable = triple.replace('-', '_')
        environment[f'CARGO_TARGET_{variable.upper()}_LINKER'] = str(clang)
        # the cc crate compiles QuickJS with the NDK compiler
        environment[f'CC_{variable}'] = str(clang)
        environment[f'AR_{variable}'] = str(archiver)
    # one Cargo call builds every target, so they also build in parallel
    _cargo(['build', '--release', *(f'--target={triple}' for triple in triples)], quiet, MODULES, environment)
    targets = []
    for folder, triple in ANDROID_TARGETS.items():
        for module in MODULES:
            built = TARGET / triple / 'release' / f'libopensc2k_{module}.so'
            targets.append(_install(built, ROOT / 'game/bin' / f'opensc2k_{module}' / folder / built.name))
        targets += build_fluidsynth.build_android(quiet=quiet, folder=folder)
    return targets


def test(quiet=False):
    """Run unit tests for each native library. The audio tests use the built FluidSynth."""
    environment = dict(os.environ)
    fluidsynth = build_fluidsynth.output_folder(host_folder()) / build_fluidsynth.LIBRARY_NAMES[host_folder()][0]
    if fluidsynth.is_file():
        environment.setdefault('OPENSC2K_FLUIDSYNTH', str(fluidsynth))
        environment.setdefault('OPENSC2K_REQUIRE_FLUIDSYNTH', '1')
    # the crates in native/core must build without Godot
    subprocess.run(['cargo', 'xtask', 'check-cores'], cwd=WORKSPACE, check=True, capture_output=quiet,
                   env=environment)
    command = ['cargo', 'test', '--release', '--workspace']
    if quiet:
        command.append('--quiet')
    subprocess.run(command, cwd=WORKSPACE, check=True, capture_output=quiet, env=environment)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--debug', action='store_true', help='Build without optimizations')
    parser.add_argument('--package', action='store_true', help='Build the library of a desktop package')
    parser.add_argument('--android', action='store_true', help='Build the libraries of the Android package')
    args = parser.parse_args()
    if args.android:
        targets = build_android()
    else:
        targets = build_package() if args.package else build('debug' if args.debug else 'release')
    for target in targets:
        print(f'Native library: {target.relative_to(ROOT)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
