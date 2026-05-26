#!/usr/bin/env python3
"""
Download glibc .so dependencies for webkit2gtk from Debian bookworm.
Extracts only .so files to the target glibc directory.
Usage: python3 download-glibc-deps.py <glibc_dir> [packages.gz_path]
"""
import gzip, os, sys, urllib.request, tarfile, io, lzma, shutil

REPOS = [
    # base_url, dist, comp
    ("https://deb.debian.org/debian", "bookworm", "main"),
    ("https://deb.debian.org/debian", "bookworm", "contrib"),
    ("https://deb.debian.org/debian", "bookworm", "non-free"),
    ("https://deb.debian.org/debian", "bookworm", "non-free-firmware"),
    ("https://security.debian.org/debian-security", "bookworm-security", "main"),
    ("https://security.debian.org/debian-security", "bookworm-security", "contrib"),
    ("https://security.debian.org/debian-security", "bookworm-security", "non-free"),
    ("https://security.debian.org/debian-security", "bookworm-security", "non-free-firmware"),
    ("https://deb.debian.org/debian", "bookworm-updates", "main"),
    ("https://deb.debian.org/debian", "bookworm-updates", "contrib"),
    ("https://deb.debian.org/debian", "bookworm-updates", "non-free"),
    ("https://deb.debian.org/debian", "bookworm-updates", "non-free-firmware"),
]

def fetch_url(url):
    """Fetch URL, try .gz first then .xz fallback."""
    try:
        resp = urllib.request.urlopen(url)
        return resp.read()
    except urllib.error.HTTPError:
        if url.endswith('.gz'):
            xz_url = url[:-3] + '.xz'
            try:
                resp = urllib.request.urlopen(xz_url)
                return lzma.decompress(resp.read())
            except Exception:
                pass
    return None

def parse_packages(packages_gz_path=None):
    if packages_gz_path and os.path.exists(packages_gz_path):
        with open(packages_gz_path, 'rb') as f:
            data = f.read()
        try:
            return _parse_packages_data(gzip.decompress(data))
        except Exception:
            try:
                return _parse_packages_data(lzma.decompress(data))
            except Exception:
                return _parse_packages_data(data)

    # Download from all repos and merge
    pkgs = {}
    for base_url, dist, comp in REPOS:
        url = f"{base_url}/dists/{dist}/{comp}/binary-amd64/Packages.gz"
        data = fetch_url(url)
        if data:
            repo_pkgs = _parse_packages_data(gzip.decompress(data) if data[:2] == b'\x1f\x8b' else data)
            for name, info in repo_pkgs.items():
                if name not in pkgs:
                    pkgs[name] = info
    return pkgs

def _parse_packages_data(data):
    pkgs = {}
    current = {}
    for line in data.decode('utf-8', errors='replace').split('\n'):
        line = line.strip()
        if line == '':
            if current.get('Package'):
                pkgs[current['Package']] = current
            current = {}
        elif ':' in line:
            k, v = line.split(':', 1)
            current[k.strip()] = v.strip()
    if current.get('Package'):
        pkgs[current['Package']] = current
    return pkgs

def resolve_deps(pkg_name, pkgs, resolved=None):
    if resolved is None:
        resolved = set()
    if pkg_name in resolved:
        return resolved
    resolved.add(pkg_name)
    pkg = pkgs.get(pkg_name)
    if not pkg:
        return resolved
    for dep_group in pkg.get('Depends', '').split(','):
        dep = dep_group.split('|')[0].strip().split('(')[0].strip()
        if dep and dep not in resolved:
            resolve_deps(dep, pkgs, resolved)
    return resolved

def extract_so_from_deb(deb_path):
    """Extract .so files from a .deb archive. Returns list of (name, data, is_link, link_target)."""
    files = []
    with open(deb_path, 'rb') as f:
        magic = f.read(8)
        if magic != b'!<arch>\n':
            return files
        while True:
            header = f.read(60)
            if len(header) < 60:
                break
            name = header[0:16].strip().decode()
            size = int(header[48:58].strip())
            if 'data.tar' in name:
                data = f.read(size)
                if '.xz' in name:
                    data = lzma.decompress(data)
                elif '.gz' in name:
                    data = gzip.decompress(data)
                tf = tarfile.open(fileobj=io.BytesIO(data))
                for m in tf.getmembers():
                    if '.so' in m.name and ('lib/' in m.name or 'usr/lib/' in m.name):
                        if m.isfile():
                            files.append((os.path.basename(m.name), tf.extractfile(m).read(), False, None))
                        elif m.issym():
                            files.append((os.path.basename(m.name), None, True, m.linkname))
                break
            else:
                f.read(size + (size % 2))
    return files

def find_pkg_for_soname(soname, pkgs):
    """Find which package provides a given .so soname by searching Filename field."""
    # Common soname -> package mappings
    SONAME_MAP = {
        'libpcre2-8.so': 'libpcre2-8-0',
        'libffi.so': 'libffi8',
        'libz.so': 'zlib1g',
        'libgmp.so': 'libgmp10',
        'libhogweed.so': 'libhogweed6',
        'libnettle.so': 'libnettle8',
        'libgnutls.so': 'libgnutls30',
        'libtasn1.so': 'libtasn1-6',
        'libunistring.so': 'libunistring5',
        'libidn2.so': 'libidn2-0',
        'libp11-kit.so': 'libp11-kit0',
        'libpthread.so': 'libc6',
        'libdl.so': 'libc6',
        'libm.so': 'libc6',
        'librt.so': 'libc6',
        'libresolv.so': 'libc6',
        'libnss_files.so': 'libc6',
        'libcrypt.so': 'libcrypt1',
        'libstdc++.so': 'libstdc++6',
        'libgcc_s.so': 'libgcc-s1',
    }

    # Check direct map first
    base = soname.split('.so')[0]
    for pattern, pkg in SONAME_MAP.items():
        if soname.startswith(pattern.rstrip('.so')):
            if pkg in pkgs:
                return pkg

    # Search package names by soname prefix
    for pkg_name in pkgs:
        pkg_base = pkg_name.rstrip('0123456789')
        if base.startswith(pkg_base) or pkg_base.startswith(base):
            return pkg_name

    return None


def check_missing_libs(glibc_dir):
    """Run ldd on all .so files in glibc_dir and return set of missing sonames."""
    missing = set()
    if not os.path.isdir(glibc_dir):
        return missing

    for f in os.listdir(glibc_dir):
        fp = os.path.join(glibc_dir, f)
        if not os.path.isfile(fp) or os.path.islink(fp):
            continue
        if '.so' not in f:
            continue
        try:
            import subprocess
            result = subprocess.run(
                ['ldd', fp],
                capture_output=True, text=True, timeout=5,
                env={**os.environ, 'LD_LIBRARY_PATH': glibc_dir}
            )
            for line in result.stdout.split('\n'):
                if 'not found' in line:
                    soname = line.strip().split()[0]
                    missing.add(soname)
        except Exception:
            pass

    return missing


def main():
    glibc_dir = sys.argv[1] if len(sys.argv) > 1 else '/usr/lib/glibc'
    packages_gz = sys.argv[2] if len(sys.argv) > 2 else None

    print(f"Target: {glibc_dir}")
    print("Parsing Packages.gz...")
    pkgs = parse_packages(packages_gz)
    print(f"  {len(pkgs)} packages")

    # Resolve deps for webkit2gtk
    needed = resolve_deps('libwebkit2gtk-4.1-0', pkgs)
    needed |= resolve_deps('libsoup-3.0-0', pkgs)

    # Filter to library packages only
    SKIP = ['-data', '-common', '-dev', 'font', 'icon', 'perl', 'adwaita',
            'hicolor', 'dictionaries', 'hunspell', 'iso-codes', 'shared-mime',
            'xkb-data', 'usrmerge', 'init-system', 'debconf', 'procps',
            'gtk-update', 'libsensors', '-config', 'emacsen']
    lib_pkgs = [p for p in sorted(needed) if p in pkgs
                and (p.startswith('lib') or p in ['zlib1g'])
                and not any(s in p for s in SKIP)]

    # Check existing .so files (both real files and their basename for matching)
    existing_files = {}  # basename -> full path (only real files)
    existing_basenames = set()  # all basenames (files + symlinks)
    if os.path.isdir(glibc_dir):
        for f in os.listdir(glibc_dir):
            fp = os.path.join(glibc_dir, f)
            if '.so' in f:
                existing_basenames.add(f)
                if os.path.isfile(fp) and not os.path.islink(fp):
                    existing_files[f] = fp

    print(f"  {len(lib_pkgs)} library packages to check")
    print(f"  {len(existing_basenames)} existing .so entries")
    print(f"  {len(existing_files)} real .so files")

    # Download and extract
    tmpdir = '/tmp/glibc-deps'
    os.makedirs(tmpdir, exist_ok=True)

    def download_and_extract(pkg):
        """Download a .deb package and extract .so files. Returns count of new files."""
        filename = pkgs[pkg].get('Filename', '')
        if not filename:
            return 0

        deb_path = os.path.join(tmpdir, f'{pkg}.deb')
        url = f'https://deb.debian.org/debian/{filename}'

        try:
            urllib.request.urlretrieve(url, deb_path)
        except Exception as e:
            print(f"    FAIL {pkg}: {e}")
            return 0

        files = extract_so_from_deb(deb_path)
        count = 0
        for fname, data, is_link, link_target in files:
            dest = os.path.join(glibc_dir, fname)
            if os.path.exists(dest):
                if os.path.islink(dest) and not os.path.exists(dest):
                    os.remove(dest)
                else:
                    continue
            if is_link:
                target_basename = os.path.basename(link_target)
                if not os.path.exists(os.path.join(glibc_dir, target_basename)):
                    pass
                os.symlink(link_target, dest)
            else:
                with open(dest, 'wb') as f:
                    f.write(data)
                existing_files[fname] = dest
            existing_basenames.add(fname)
            count += 1

        os.remove(deb_path)
        return count

    # Phase 1: Download packages from resolved dependency tree
    installed = 0
    skipped = 0
    for i, pkg in enumerate(lib_pkgs):
        pkg_base = pkg.rstrip('0123456789')
        has_any = False
        for bn in existing_basenames:
            if bn.startswith(pkg_base):
                has_any = True
                break
        if has_any:
            skipped += 1
            continue

        count = download_and_extract(pkg)
        if count > 0:
            print(f"  [{i+1}/{len(lib_pkgs)}] {pkg}: {count} files")
            installed += 1

    # Phase 2: ldd-based resolution — check all .so files for missing deps
    # This catches transitive runtime deps not in package Depends field
    print("\nPhase 2: ldd-based missing lib resolution...")
    MAX_ROUNDS = 10
    for round_num in range(MAX_ROUNDS):
        missing = check_missing_libs(glibc_dir)
        if not missing:
            print(f"  Round {round_num+1}: all libs satisfied!")
            break

        print(f"  Round {round_num+1}: {len(missing)} missing libs: {', '.join(sorted(missing))}")

        resolved_this_round = 0
        for soname in sorted(missing):
            pkg = find_pkg_for_soname(soname, pkgs)
            if not pkg:
                print(f"    {soname}: no package found")
                continue

            # Check if already downloaded
            pkg_base = pkg.rstrip('0123456789')
            already_have = any(bn.startswith(pkg_base) for bn in existing_basenames)
            if already_have:
                continue

            print(f"    {soname} -> {pkg}")
            count = download_and_extract(pkg)
            if count > 0:
                installed += 1
                resolved_this_round += 1

        if resolved_this_round == 0:
            print(f"  No more packages to resolve")
            break

    # Robust symlink creation
    created = 0
    for fname, fpath in list(existing_files.items()):
        if '.so.' not in fname:
            continue
        parts = fname.split('.so.')
        if len(parts) != 2:
            continue
        base = parts[0]
        ver = parts[1]
        ver_parts = ver.split('.')

        for i in range(1, len(ver_parts)):
            link_name = f'{base}.so.{".".join(ver_parts[:i])}'
            link_path = os.path.join(glibc_dir, link_name)
            if not os.path.exists(link_path):
                os.symlink(fname, link_path)
                created += 1
            elif os.path.islink(link_path) and not os.path.exists(link_path):
                os.remove(link_path)
                os.symlink(fname, link_path)
                created += 1

        base_link = os.path.join(glibc_dir, f'{base}.so')
        if not os.path.exists(base_link):
            os.symlink(fname, base_link)
            created += 1
        elif os.path.islink(base_link) and not os.path.exists(base_link):
            os.remove(base_link)
            os.symlink(fname, base_link)
            created += 1

    # Final pass: fix broken symlinks
    fixed = 0
    if os.path.isdir(glibc_dir):
        for f in os.listdir(glibc_dir):
            fp = os.path.join(glibc_dir, f)
            if os.path.islink(fp) and not os.path.exists(fp):
                target = os.readlink(fp)
                target_base = os.path.basename(target)
                if target_base in existing_files:
                    os.remove(fp)
                    os.symlink(target_base, fp)
                    fixed += 1
                else:
                    for real_name in existing_files:
                        if real_name.startswith(f + '.'):
                            os.remove(fp)
                            os.symlink(real_name, fp)
                            fixed += 1
                            break

    shutil.rmtree(tmpdir, ignore_errors=True)
    print(f"\nDone: {installed} packages installed, {skipped} skipped")
    print(f"  Symlinks created: {created}, broken symlinks fixed: {fixed}")

if __name__ == '__main__':
    main()
