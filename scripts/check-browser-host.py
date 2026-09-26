#!/usr/bin/env python3
"""Run the actual native executable over framed stdin/stdout and a temporary private socket."""
import base64, hashlib, json, os, socket, struct, subprocess, tempfile, uuid
from pathlib import Path
root=Path(__file__).resolve().parent.parent
binary=Path(subprocess.check_output(['swift','build','--show-bin-path'],cwd=root,text=True).strip())/'ThreadBrowserHost'
manifest=json.loads((root/'BrowserExtensions/Chromium/manifest.json').read_text())
digest=hashlib.sha256(base64.b64decode(manifest['key'])).hexdigest()[:32]
origin='chrome-extension://'+''.join(chr(97+int(c,16)) for c in digest)+'/'
def frame(message):
 data=json.dumps(message).encode();return struct.pack('=I',len(data))+data
with tempfile.TemporaryDirectory(prefix='tbr-',dir='/private/tmp') as directory:
 path=directory+'/b.sock'
 receiver=socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM);receiver.bind(path);os.chmod(path,0o600);receiver.settimeout(2)
 message={'version':1,'kind':'activated','browser':'chrome','connection':str(uuid.uuid4()),'sequence':1,'isPrivate':False,
          'application':{'bundleIdentifier':'com.google.Chrome.canary'},'tabID':4,'windowID':3,'url':'https://example.com/docs?secret=one#token','title':'Docs','active':True}
 private=dict(message,isPrivate=True,sequence=2,url='https://private.invalid/secret')
 process=subprocess.run([str(binary),origin],input=frame(message)+frame(private),env=dict(os.environ,THREAD_BROWSER_SOCKET=path),capture_output=True,timeout=5)
 assert process.returncode==0,process.stderr.decode()
 forwarded=json.loads(receiver.recv(8192));ended=json.loads(receiver.recv(8192))
 assert forwarded['url']=='https://example.com/docs',forwarded
 assert 'application' not in forwarded, 'Fixture parent is not a browser; extension identity must be stripped'
 assert ended['kind']=='disconnected'
 assert 'url' not in ended
 first_length=struct.unpack('=I',process.stdout[:4])[0]
 assert json.loads(process.stdout[4:4+first_length])['forwarded'] is True
 offset=4+first_length;length=struct.unpack('=I',process.stdout[offset:offset+4])[0]
 assert json.loads(process.stdout[offset+4:offset+4+length])['forwarded'] is False
 rejected=subprocess.run([str(binary),'chrome-extension://'+'a'*32+'/'],input=frame(message),capture_output=True,timeout=5)
 assert rejected.returncode!=0 and rejected.stdout==b''
 oversized=subprocess.run([str(binary),origin],input=struct.pack('=I',2**31),capture_output=True,timeout=5)
 assert oversized.returncode!=0
print('Native browser host: origin policy, framing, redaction, private exclusion, disconnect, oversized rejection passed.')
