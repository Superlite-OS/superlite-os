import subprocess
import sys
import time

def run_ssh(host, user, password, command):
    # Using plink if available (common on Windows) or ssh with a small hack
    # Since we can't easily do interactive password in a simple subprocess call without extras
    # we will use a small python script that the user can run or we can try to use sshpass if it were there.
    # However, since I am an agent, I will provide the script for the USER to run locally.
    
    script = f"""
import paramiko
import sys

def debug_remote():
    host = '{host}'
    user = '{user}'
    password = '{password}'
    
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        print(f"Connecting to {{host}}...")
        client.connect(host, username=user, password=password)
        
        commands = [
            "echo '--- BINARY INFO ---'",
            "ls -l /usr/bin/superlite-files /usr/bin/google-chrome-stable",
            "file /usr/bin/superlite-files /usr/lib/glibc/bin/chrome",
            "echo '--- LDD SUPERLITE-FILES ---'",
            "ldd /usr/bin/superlite-files",
            "echo '--- LDD CHROME (GLIBC) ---'",
            "export LD_LIBRARY_PATH=/usr/lib/glibc",
            "/usr/lib/glibc/ld-linux-x86-64.so.2 --library-path /usr/lib/glibc --list /usr/lib/glibc/bin/chrome",
            "echo '--- EXECUTION TEST ---'",
            "timeout 2 /usr/bin/superlite-files 2>&1 || true",
            "timeout 2 /usr/bin/google-chrome-stable --version 2>&1 || true"
        ]
        
        for cmd in commands:
            print(f"\\nExecuting: {{cmd}}")
            stdin, stdout, stderr = client.exec_command(cmd)
            print(stdout.read().decode())
            err = stderr.read().decode()
            if err:
                print(f"STDERR: {{err}}")
                
    except Exception as e:
        print(f"Error: {{e}}")
    finally:
        client.close()

if __name__ == '__main__':
    debug_remote()
"""
    return script

if __name__ == '__main__':
    print("Saving remote-debug.py helper...")
    # I will save this as a separate file so the user can run it if they have paramiko
    # But I have already identified the main issues:
    # 1. python3 was missing in build.sh (breaks download-glibc-deps.py -> breaks Chrome)
    # 2. gtk+3.0 was missing in packages.list (breaks native musl superlite-files)
    # 3. libxkbcommon was missing in packages.list (breaks most Wayland apps)
