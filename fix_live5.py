import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.14', username='root', password='kelvin123', timeout=10)

def r(cmd, t=30):
    i, o, e = ssh.exec_command(cmd, timeout=t)
    return o.read().decode('utf-8', errors='replace').strip()

# 1. Write ar extractor to file on remote
r("cat > /tmp/extract_ar.py << 'PYEOF'\nimport struct\nf=open('/tmp/libsystemd0.deb','rb')\nf.read(8)\nwhile True:\n    hdr=f.read(60)\n    if len(hdr)<60: break\n    sz=int(hdr[48:58].strip())\n    if b'data.tar' in hdr[:16]:\n        open('/tmp/d.tar','wb').write(f.read(sz))\n        break\n    f.read(sz+sz%2)\nf.close()\nprint('OK')\nPYEOF")

# 2. Run it
print('extract:', r('python3 /tmp/extract_ar.py 2>&1'))

# 3. Extract tar
print('tar:', r('cd /tmp && tar xf d.tar 2>&1 && find /tmp/lib -name "libsystemd*" 2>/dev/null'))

# 4. Copy
print('copy:', r('cp /tmp/lib/x86_64-linux-gnu/libsystemd.so.0* /usr/lib/glibc/ 2>&1 && ls /usr/lib/glibc/libsystemd*'))

# 5. Test terax
print('terax:', r('/bin/terax --version 2>&1')[:100])

# 6. Chrome wrapper
print('chrome:', r('cat /opt/google/chrome/chrome 2>&1')[:200])

# 7. doublecmd wrapper
print('doublecmd:', r('cat /bin/doublecmd 2>&1 | head -3')[:200])

# 8. curl wrapper
print('curl:', r('cat /usr/local/bin/curl-impersonate-chrome 2>&1 | head -3')[:200])

ssh.close()
