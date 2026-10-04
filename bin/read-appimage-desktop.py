#!/usr/bin/python3
"""Print one root desktop file from a type-2 AppImage without executing it.

The AppImage runtime is an ELF. appimagetool stores the squashfs immediately
after the section header table. This reads that filesystem with unsquashfs.
"""

import fcntl
import os
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time

MAX_BYTES = 524288000
MAX_DESKTOP = 65536
MAX_INODES = 200000
MAX_LIST = 1024 * 1024
TIMEOUT = 20
UNSQUASHFS = "/usr/bin/unsquashfs"


class ReadError(Exception):
    pass


def die(code, message):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def terminate(proc):
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def capture(proc, limit):
    data = bytearray()
    end = time.monotonic() + TIMEOUT
    fd = proc.stdout.fileno()
    os.set_blocking(fd, False)
    try:
        while True:
            if len(data) > limit or time.monotonic() >= end:
                terminate(proc)
                raise ReadError("unsquashfs output exceeded its limit")
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                if proc.poll() is not None:
                    break
                time.sleep(0.02)
                continue
            if chunk == b"":
                if proc.poll() is not None:
                    break
                time.sleep(0.02)
                continue
            data.extend(chunk)
        rc = proc.wait(timeout=5)
        return rc, bytes(data)
    finally:
        proc.stdout.close()


def run_unsquash(args, address_limit):
    def preexec():
        os.setsid()
        os.umask(0o077)
        limit = (address_limit, address_limit)
        resource_set = __import__("resource")
        resource_set.setrlimit(resource_set.RLIMIT_AS, limit)
        resource_set.setrlimit(resource_set.RLIMIT_CPU, (TIMEOUT, TIMEOUT))

    try:
        proc = subprocess.Popen(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            preexec_fn=preexec,
        )
    except FileNotFoundError:
        die(3, "unsquashfs is not installed")
    return proc


def read_exact(fd, count):
    buf = b""
    while len(buf) < count:
        chunk = os.read(fd, count - len(buf))
        if not chunk:
            break
        buf += chunk
    return buf


def elf_squashfs_offset(fd):
    os.lseek(fd, 0, os.SEEK_SET)
    hdr = read_exact(fd, 64)
    if len(hdr) < 64 or hdr[:4] != b"\x7fELF" or hdr[5] != 1:
        raise ReadError("not a little-endian ELF")
    if hdr[8:11] != b"AI\x02":
        raise ReadError("not a type-2 AppImage")
    elf_class = hdr[4]
    if elf_class == 2:
        e_shoff = struct.unpack_from("<Q", hdr, 40)[0]
        e_shentsize = struct.unpack_from("<H", hdr, 58)[0]
        e_shnum = struct.unpack_from("<H", hdr, 60)[0]
        size_at = 32
        size_fmt = "<Q"
    elif elf_class == 1:
        e_shoff = struct.unpack_from("<I", hdr, 32)[0]
        e_shentsize = struct.unpack_from("<H", hdr, 46)[0]
        e_shnum = struct.unpack_from("<H", hdr, 48)[0]
        size_at = 20
        size_fmt = "<I"
    else:
        raise ReadError("unsupported ELF class")
    if e_shoff <= 0 or e_shentsize < 40:
        raise ReadError("ELF has no section table")
    if e_shnum == 0:
        os.lseek(fd, e_shoff, os.SEEK_SET)
        section = read_exact(fd, e_shentsize)
        if len(section) < e_shentsize:
            raise ReadError("truncated section header")
        e_shnum = struct.unpack_from(size_fmt, section, size_at)[0]
    if e_shnum <= 0 or e_shnum > 10000:
        raise ReadError("unreasonable section count")
    return e_shoff + e_shentsize * e_shnum


def squashfs_bytes(fd, offset, file_size):
    if offset <= 0 or offset >= file_size or file_size - offset < 96:
        raise ReadError("squashfs offset is outside the file")
    os.lseek(fd, offset, os.SEEK_SET)
    header = read_exact(fd, 96)
    if len(header) < 96:
        raise ReadError("truncated squashfs superblock")
    magic, inodes, _mtime, block, _fragments, comp = struct.unpack_from("<5IH", header, 0)
    if magic != 0x73717368:
        raise ReadError("squashfs magic is missing")
    if inodes <= 0 or inodes > MAX_INODES:
        raise ReadError("squashfs inode count is out of range")
    if block < 4096 or block > 1048576 or block & (block - 1):
        raise ReadError("squashfs block size is out of range")
    if comp not in (1, 2, 3, 4, 5, 6):
        raise ReadError("squashfs compression is unknown")
    used = struct.unpack_from("<Q", header, 40)[0]
    if used < 96 or offset + used > file_size:
        raise ReadError("squashfs size is out of range")
    return used


def copy_range(fd, offset, nbytes, dest):
    os.lseek(fd, offset, os.SEEK_SET)
    left = nbytes
    while left:
        chunk = os.read(fd, min(1024 * 1024, left))
        if not chunk:
            raise ReadError("squashfs copy ended early")
        os.write(dest, chunk)
        left -= len(chunk)


def desktop_name_ok(name):
    if not name or len(name) > 128 or not name.endswith(".desktop"):
        return False
    if name.startswith("-") or name.startswith("."):
        return False
    for char in name:
        if char in "/\\\x00" or ord(char) < 32 or ord(char) == 127:
            return False
    return True


def root_desktop_names(listing):
    found = []
    marker = "squashfs-root/"
    for line in listing.splitlines():
        if not line.startswith("-"):
            continue
        pos = line.rfind(marker)
        if pos < 0:
            continue
        name = line[pos + len(marker) :]
        if "/" in name or not desktop_name_ok(name):
            continue
        found.append(name)
    found.sort()
    return found


def looks_like_desktop(data):
    if not data or len(data) > MAX_DESKTOP or b"\0" in data:
        return False
    if b"[Desktop Entry]" not in data:
        return False
    return any(line.startswith(b"Name=") for line in data.splitlines())


def open_regular(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    except OSError as err:
        raise ReadError("could not open the AppImage") from err
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise ReadError("AppImage path is not a regular file")
        if info.st_size <= 0 or info.st_size > MAX_BYTES:
            raise ReadError("AppImage size is out of range")
        flags = fcntl.fcntl(fd, fcntl.F_GETFL)
        fcntl.fcntl(fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
        return fd, info.st_size
    except Exception:
        os.close(fd)
        raise


def unsquashfs_ready():
    try:
        info = os.lstat(UNSQUASHFS)
    except OSError:
        die(3, "unsquashfs is not installed")
    if not stat.S_ISREG(info.st_mode) or not os.access(UNSQUASHFS, os.X_OK):
        die(3, "unsquashfs is not installed")
    real = os.path.realpath(UNSQUASHFS)
    if not real.startswith("/usr/"):
        die(3, "unsquashfs is not installed")


def main(argv):
    if len(argv) != 2 or not argv[1]:
        die(2, "usage: read-appimage-desktop.py <path>")
    unsquashfs_ready()
    try:
        fd, file_size = open_regular(argv[1])
    except ReadError as err:
        die(2, str(err))
    try:
        try:
            offset = elf_squashfs_offset(fd)
            used = squashfs_bytes(fd, offset, file_size)
        except ReadError as err:
            die(2, str(err))
        with tempfile.TemporaryDirectory(prefix="omarchy-appimage-") as temp:
            os.chmod(temp, 0o700)
            image = os.path.join(temp, "filesystem")
            out = os.open(image, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_CLOEXEC, 0o600)
            try:
                copy_range(fd, offset, used, out)
            finally:
                os.close(out)
            address_limit = min(800 * 1024 * 1024, max(256 * 1024 * 1024, used + 64 * 1024 * 1024))
            common = [
                UNSQUASHFS,
                "-quiet",
                "-no-progress",
                "-processors",
                "1",
                "-mem",
                "32M",
                "-strict-errors",
            ]
            listing = run_unsquash(
                common + ["-llc", "-max-depth", "1", image],
                address_limit,
            )
            try:
                rc, listed = capture(listing, MAX_LIST)
            except (ReadError, subprocess.TimeoutExpired) as err:
                die(2, str(err))
            if rc != 0:
                die(2, "could not list the AppImage filesystem")
            names = root_desktop_names(listed.decode("utf-8", "replace"))
            if not names:
                die(2, "no root desktop entry")
            cat = run_unsquash(
                common + ["-cat", "-no-wildcards", image, names[0]],
                address_limit,
            )
            try:
                rc, body = capture(cat, MAX_DESKTOP)
            except (ReadError, subprocess.TimeoutExpired) as err:
                die(2, str(err))
            if rc != 0 or not looks_like_desktop(body):
                die(2, "could not read the desktop entry")
            sys.stdout.buffer.write(body)
    finally:
        os.close(fd)


if __name__ == "__main__":
    main(sys.argv)
