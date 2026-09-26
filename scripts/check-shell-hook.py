#!/usr/bin/env python3
"""Verify the packaged sender protocol from a clean interactive zsh session."""
import os,json,socket,subprocess,tempfile,pathlib
root=pathlib.Path(__file__).resolve().parent.parent
bindir=subprocess.check_output(['swift','build','--show-bin-path'],cwd=root,text=True).strip()
with tempfile.TemporaryDirectory(prefix='thread-zsh-',dir='/private/tmp') as directory:
 path=directory+'/s.sock'
 server=socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM);server.bind(path);os.chmod(path,0o600);server.settimeout(2)
 env=dict(os.environ,THREAD_SHELL_SENDER=bindir+'/ThreadShellSend',THREAD_SOCKET_PATH=path,THREAD_TEST_HOOK=str(root/'ShellIntegration/zsh/thread.zsh'),THREAD_TEST_DIRECTORY=directory)
 code='source "$THREAD_TEST_HOOK"; cd "$THREAD_TEST_DIRECTORY"; false; _thread_precmd; exit 0'
 run=subprocess.run(['/bin/zsh','-f','-i','-c',code],env=env,capture_output=True,text=True,timeout=10)
 assert run.returncode==0,run.stderr
 messages=[json.loads(server.recv(8192)) for _ in range(4)]
 assert [x['kind'] for x in messages]==['directory','directory','completed','ended'],messages
 assert [x['sequence'] for x in messages]==[1,2,3,4]
 assert messages[2]['exitStatus']==1
 assert messages[1]['workingDirectory']==directory
 assert len({x['session'] for x in messages})==1
 assert all('command' not in x for x in messages)
 print('Native sender + isolated interactive zsh: initial cwd, cd, nonzero completion, ordered exit passed.')
