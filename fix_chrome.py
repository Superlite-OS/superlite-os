import paramiko, time, base64

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.14', username='root', password='kelvin123', timeout=10)

def run(cmd, timeout=15):
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode()
    err = stderr.read().decode()
    return out.strip(), err.strip()

SCRIPT = r'''#!/bin/sh
exec > /tmp/fix_chrome_final.log 2>&1
echo "=== Chrome final fix $(date) ==="

export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/tmp/0-runtime-dir
export LD_LIBRARY_PATH=/usr/lib/glibc
export DISPLAY=:0
export GSETTINGS_BACKEND=memory

echo "=== TEST 1: headless ==="
timeout 15 /usr/lib/glibc/bin/chrome --no-sandbox --headless=new --disable-gpu --dump-dom about:blank 2>/tmp/cf1
R=$?
echo "EXIT=$R"
if [ $R -eq 0 ]; then
    echo "SUCCESS: CHROME_HEADLESS"
    head -3 /tmp/cf1
else
    grep -i 'fatal\|error' /tmp/cf1 | head -5
fi

echo ""
echo "=== TEST 2: wayland GUI ==="
/usr/lib/glibc/bin/chrome --no-sandbox --disable-gpu --ozone-platform=wayland </dev/null 2>/tmp/cf2 &
CP=$!
sleep 8
if kill -0 $CP 2>/dev/null; then
    echo "SUCCESS: CHROME_WAYLAND PID=$CP"
    kill $CP 2>/dev/null
else
    echo "FAIL"
    cat /tmp/cf2 | tail -5
fi

echo ""
echo "=== TEST 3: X11 GUI ==="
/usr/lib/glibc/bin/chrome --no-sandbox --disable-gpu </dev/null 2>/tmp/cf3 &
CP=$!
sleep 8
if kill -0 $CP 2>/dev/null; then
    echo "SUCCESS: CHROME_X11 PID=$CP"
    kill $CP 2>/dev/null
else
    echo "FAIL"
    cat /tmp/cf3 | tail -5
fi

echo ""
echo "=== Update wrapper ==="
cat > /usr/bin/google-chrome-stable << 'WRAPPER'
#!/bin/sh
[ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY=wayland-0
[ -z "$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR=/tmp/0-runtime-dir
export CHROME_VERSION_EXTRA=stable
export LD_LIBRARY_PATH=/usr/lib/glibc
export GSETTINGS_BACKEND=memory
exec /usr/lib/glibc/bin/chrome --no-sandbox --disable-gpu "$@"
WRAPPER
chmod +x /usr/bin/google-chrome-stable
echo "wrapper updated"

echo ""
echo "=== DONE ==="
'''

encoded = base64.b64encode(SCRIPT.encode()).decode()
print("Writing script...")
run(f"echo '{encoded}' | base64 -d > /tmp/fix_chrome_final.sh && chmod +x /tmp/fix_chrome_final.sh")
print("Running...")
run("nohup sh /tmp/fix_chrome_final.sh &", timeout=5)
time.sleep(45)
print("\n=== RESULTS ===")
out, _ = run("cat /tmp/fix_chrome_final.log")
print(out.encode('ascii', 'replace').decode())
ssh.close()
