"""Exercise staged publication over an OpenSSH subsystem channel. Copyright 2026 Qore Technologies, s.r.o."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import struct
import subprocess
import sys
from threading import Barrier


def u32(value):
    return struct.pack(">I", value)


def field(value):
    return u32(len(value)) + value


class Client:
    def __init__(self, process):
        self.process = process
        self.serial = 0
        self.send(1, u32(3))
        assert self.receive() == b"\x02" + u32(3)

    def send(self, opcode, payload):
        self.process.stdin.write(field(bytes([opcode]) + payload))
        self.process.stdin.flush()

    def receive(self):
        size, = struct.unpack(">I", self.process.stdout.read(4))
        packet = self.process.stdout.read(size)
        assert len(packet) == size
        return packet

    def request(self, opcode, payload, *, discard_reply=False):
        self.serial += 1
        self.send(opcode, u32(self.serial) + payload)
        if discard_reply:
            return
        packet = self.receive()
        assert packet[1:5] == u32(self.serial)
        return packet[0], packet[5:]

    def status(self, opcode, payload, *, success=True):
        kind, response = self.request(opcode, payload)
        assert kind == 101 and (response[:4] == u32(0)) == success, (opcode, kind, response)
        return success

    def open(self, path):
        kind, handle = self.request(3, field(path) + u32(2 | 8 | 32) + u32(0))
        assert kind == 102, (path, handle)
        return handle

    def write(self, handle, offset, data, *, success=True):
        self.status(6, handle + struct.pack(">Q", offset) + field(data), success=success)

    def stage(self, path, data):
        handle = self.open(path)
        self.write(handle, 0, data)
        self.status(4, handle)
        return handle

    def rename(self, source, target, *, success=True):
        self.status(18, field(source) + field(target), success=success)

    def exists(self, path):
        kind, result = self.request(17, field(path))
        assert kind == 105 or (kind == 101 and result[:4] != u32(0))
        return kind == 105


@contextmanager
def session(port, principal):
    command = ["ssh", "-F", "/dev/null", "-oBatchMode=yes", "-oPreferredAuthentications=none",
               "-oStrictHostKeyChecking=no", "-oUserKnownHostsFile=/dev/null", "-oLogLevel=ERROR",
               "-p", str(port), "-s", principal + "@127.0.0.1", "sftp"]
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE) as process:
        try:
            yield Client(process)
        finally:
            process.stdin.close()
            # EOF terminates the server's request loop, including when the last reply is unread.
            process.wait(timeout=20)


def qualify(port):
    stage, final = b"/staging/member", b"/inbound/order"
    with session(port, "alice") as client:
        handle = client.open(stage)
        client.write(handle, 0, b"abandoned")
        client.rename(stage, final, success=False)
        assert not client.exists(final)
    with session(port, "alice") as client:
        assert not client.exists(stage)
        handle = client.open(stage)
        client.write(handle, 0, b"prefix")
        client.write(handle, 9, b"gap", success=False)
        client.status(4, handle, success=False)
        handle = client.stage(stage, b"complete\0member")
        client.write(handle, 0, b"stale", success=False)
        assert not client.exists(final)
    with session(port, "bob") as client:
        assert not client.exists(stage)
        client.rename(stage, final, success=False)
        client.status(3, field(final) + u32(2 | 8) + u32(0), success=False)
    with session(port, "alice") as client:
        client.request(18, field(stage) + field(final), discard_reply=True)
    with session(port, "alice") as client:
        assert client.exists(final) and not client.exists(stage)
        client.stage(stage, b"")
        client.rename(stage, final, success=False)
        client.rename(stage, b"/inbound/empty")
        kind, handle = client.request(3, field(final) + u32(1) + u32(0))
        assert kind == 102
        assert client.request(5, handle + struct.pack(">Q", 0) + u32(100)) == (103, field(b"complete\0member"))
        client.status(4, handle)

    barrier = Barrier(2, timeout=20)

    def compete(name):
        with session(port, "alice") as client:
            path = b"/staging/" + name
            client.stage(path, name)
            barrier.wait()
            kind, response = client.request(18, field(path) + field(b"/inbound/race"))
            assert kind == 101
            return response[:4] == u32(0)

    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(compete, [b"first", b"second"])) == [False, True]

    with session(port, "alice") as client:
        handle = client.open(b"/staging/cancel")
        client.write(handle, 0, b"interrupted")
        assert client.process.stdout.read() == b""
    with session(port, "alice") as client:
        assert not client.exists(b"/staging/cancel")
        client.open(b"/staging/cancel")
        for index in range(65):
            handle = client.open(f"/staging/list-{index}".encode())
            client.status(4, handle)
        kind, directory = client.request(11, field(b"/staging"))
        assert kind == 102
        # The losing racer retains its closed stage alongside cancel and the 65 list entries.
        for expected in (64, 3):
            kind, names = client.request(12, directory)
            assert kind == 104 and names[:4] == u32(expected), (kind, names[:4], expected)
        kind, status = client.request(12, directory)
        assert kind == 101 and status[:4] == u32(1)
        client.status(4, directory)


if __name__ == "__main__":
    qualify(int(sys.argv[1]))
