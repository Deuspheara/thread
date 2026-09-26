#!/usr/bin/env python3
"""Exercise the actual native host's duplex restore path with framed extension messages."""
import time, json, os, select, socket, struct, subprocess, tempfile, uuid
from pathlib import Path
root = Path(__file__).resolve().parent.parent
binary = Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip()) / 'ThreadBrowserHost'
def write(pipe, payload):
    data = json.dumps(payload).encode()
    pipe.write(struct.pack('=I', len(data)) + data)
    pipe.flush()
def read(pipe):
    assert select.select([pipe], [], [], 4)[0], 'native host output timed out'
    length = struct.unpack('=I', pipe.read(4))[0]
    return json.loads(pipe.read(length))
with tempfile.TemporaryDirectory(prefix='tbr-', dir='/private/tmp') as directory:
    root_path = Path(directory)
    observation = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    observation.bind(str(root_path / 'activity.sock'))
    os.chmod(root_path / 'activity.sock', 0o600)
    connection, request = str(uuid.uuid4()), str(uuid.uuid4())
    reply_path = root_path / 'r' / request
    reply_path.mkdir(parents=True, mode=0o700)
    reply = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    reply.bind(str(reply_path / 's')); os.chmod(reply_path / 's', 0o600); reply.settimeout(4)
    process = subprocess.Popen([str(binary), 'chrome-extension://ffjhibkehjmapladhgbmjfpamjpglhcb/'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
        env=dict(os.environ, THREAD_BROWSER_SOCKET=str(root_path / 'activity.sock')))
    try:
        write(process.stdin, dict(version=1, kind='connected', browser='chrome', connection=connection, sequence=1, isPrivate=False))
        assert read(process.stdout)['forwarded']
        command = dict(expiresAt=(time.time()+3.5)*1000, version=1, kind='restoreTab', id=request, connection=connection, url='https://example.com/docs', tabID=4)
        sender = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sender.sendto(json.dumps(command).encode(), str(root_path / 'c' / connection / 's'))
        assert read(process.stdout) == command
        result = dict(version=1, kind='restoreResult', id=request, connection=connection, outcome='focused')
        write(process.stdin, dict(result, connection=str(uuid.uuid4())))
        reply.settimeout(0.15)
        try:
            reply.recv(8192)
            raise AssertionError('uncorrelated acknowledgment escaped')
        except socket.timeout:
            pass
        reply.settimeout(4)
        write(process.stdin, result)
        assert json.loads(reply.recv(8192)) == result
        process.stdin.close()
        assert process.wait(timeout=4) == 0
    finally:
        if process.poll() is None: process.kill(); process.wait()
        observation.close(); reply.close()
print('Native browser restoration: idle command delivery and correlated acknowledgment passed.')
