import { useState, useEffect, type FC } from 'react';
import './Docs.css';

interface DocSection {
  id: string;
  title: string;
  icon: string;
  content: string;
}

const SECTIONS: DocSection[] = [
  {
    id: 'introduction',
    title: 'Introduction',
    icon: 'fa-solid fa-circle-info',
    content: `SuperLite OS is a complete Linux desktop built on Alpine Linux. It delivers a full Wayland environment with Chrome, a dual-pane file manager, notifications, and a unified dark theme — all in roughly 300MB.

Unlike traditional lightweight distributions that strip features to save space, SuperLite rethinks how components fit together. It uses Alpine's musl libc as the foundation, then layers Debian's glibc packages on top for complex binaries that need them. The result: a system that is both tiny and capable.

## Why SuperLite?

Most lightweight distros make you choose: small size or real functionality. SuperLite refuses that tradeoff. By combining Alpine's package efficiency with a custom glibc isolation layer, it runs mainstream software like Google Chrome without containers, VMs, or Flatpak overhead.

The ISO builds in 15 minutes with three shell scripts. No Yocto. No BitBake. No 50GB build environments.`,
  },
  {
    id: 'architecture',
    title: 'Architecture',
    icon: 'fa-solid fa-sitemap',
    content: `SuperLite's build system is intentionally minimal. Three scripts handle everything:

- \`build.sh\` — Entry point. Sets up the build environment (Docker or native Alpine).
- \`mkimage.sh\` — Alpine's native image builder. Handles squashfs, kernel, initramfs.
- \`mkimg.superlite.sh\` + \`genapkovl-superlite.sh\` — Profile (packages, kernel modules) and overlay (config, services, dotfiles).

## How it boots

The ISO boots via Alpine's standard init system. A custom \`/sbin/init\` wrapper detects whether you're running from USB or installed disk, then sets up overlayfs if a writable partition exists. This keeps RAM usage low — the rootfs stays read-only on the USB, and writes go to a dedicated ext4 partition.

## Build comparison

| | Yocto / BitBake | SuperLite OS |
|---|---|---|
| Build time | 2–6 hours | 5–15 minutes |
| Disk usage | 50GB+ | Less than 1GB |
| Complexity | Layers, recipes, bitbake | 3 shell scripts |
| Initramfs | Custom hooks | Alpine handles it |`,
  },
  {
    id: 'zapt',
    title: 'zapt Package Manager',
    icon: 'fa-solid fa-cubes',
    content: `zapt is a custom .deb package manager built specifically for Alpine's musl environment. It downloads packages directly from the Debian pool, resolves dependencies, extracts libraries, and generates wrapper scripts that point binaries to the correct glibc libraries.

## Why zapt exists

Alpine's apk is excellent for musl-native packages. But some software — notably Google Chrome, Electron apps, and certain proprietary tools — only ships as .deb built against glibc. Rather than abandoning Alpine or using containers, zapt bridges the gap.

## How it works

\`\`\`
zapt install google-chrome

Resolving dependencies...
Downloading 63 packages from Debian Bookworm
Extracting to /usr/lib/glibc/...
Generating wrapper for google-chrome
  google-chrome installed
\`\`\`

zapt performs several steps:

1. **Downloads** the .deb and its dependency tree from Debian's package pool
2. **Checks ownership** — skips files already managed by apk to prevent conflicts
3. **Extracts** libraries to \`/usr/lib/glibc/\`, isolated from musl system paths
4. **Generates wrappers** — shell scripts that set \`LD_LIBRARY_PATH\` to the glibc directory before launching the binary
5. **Runs ldd checks** to verify all shared libraries are resolved

## Install modes

zapt supports three modes for each package:

- **full** (default) — binaries and all libraries
- **bin-only** — just the executable, reuse existing libraries
- **lib-only** — libraries only, for packages that are dependencies

## Safety

zapt never overwrites files owned by Alpine's apk. Before extracting any file, it runs \`apk info -W\` to check ownership. Conflicts are skipped silently.`,
  },
  {
    id: 'musl-glibc',
    title: 'musl + glibc Coexistence',
    icon: 'fa-solid fa-puzzle-piece',
    content: `SuperLite's core innovation is running musl and glibc side by side without containers. This is not a hack — it's a deliberate architecture that leverages how Linux actually loads shared libraries.

## The problem

Alpine Linux uses musl libc. Most desktop software (Chrome, Electron, Steam) is built against glibc. These two C libraries are not binary-compatible. A glibc binary cannot load musl libraries, and vice versa.

Traditional solutions:

- **Containers** — overhead, complexity, poor desktop integration
- **Flatpak** — large runtime downloads, sandboxing issues
- **Chroot** — manual, fragile, no desktop integration
- **Use a glibc distro** — lose Alpine's size advantage

## SuperLite's approach

SuperLite keeps Alpine's musl as the system libc. glibc binaries get their own isolated library directory at \`/usr/lib/glibc/\` containing 63 packages from Debian Bookworm. Each glibc binary has a wrapper script:

\`\`\`bash
#!/bin/sh
export LD_LIBRARY_PATH=/usr/lib/glibc/lib:/usr/lib/glibc/usr/lib
exec /usr/lib/glibc/usr/bin/google-chrome "$@"
\`\`\`

This is simple, transparent, and effective. The kernel doesn't care which libc a process uses — it only loads ELF binaries. The dynamic linker handles the rest.

## Why 63 packages?

Chrome depends on a deep tree of shared libraries: libgtk, libglib, libnss, libnspr, libx11, and dozens more. SuperLite's build system parses Debian's Packages.gz to resolve the full dependency tree and downloads exactly what's needed — nothing more.

## The result

- Chrome runs natively, not in a sandbox
- No container runtime overhead
- Full desktop integration (clipboard, file dialogs, notifications)
- Updates via zapt, same as any other package
- Total glibc footprint: roughly 120MB`,
  },
  {
    id: 'desktop',
    title: 'Desktop Environment',
    icon: 'fa-solid fa-desktop',
    content: `SuperLite uses LabWC, an OpenBox-style Wayland compositor. This was chosen over Sway, Hyprland, and other tiling compositors because OpenBox-style window management is familiar to most Linux users and requires zero configuration to be productive.

## Components

| Component | Role |
|---|---|
| LabWC | Wayland compositor, OpenBox-style |
| Waybar | 3-panel status bar (system, workspaces, controls) |
| Foot | Wayland-native terminal |
| Mako | Notification daemon |
| tofi | Full-screen app launcher |
| Double Commander | Dual-pane file manager |
| PipeWire | Audio stack |
| Google Chrome | Browser via glibc isolation |
| Catppuccin Mocha | Unified dark theme |

## Theme

Every component uses the Catppuccin Mocha palette. This was a deliberate choice — Catppuccin is the most widely adopted dark theme in the Linux community, which means users are already familiar with it. The theme covers:

- LabWC window decorations
- Waybar styling
- Mako notification popups
- tofi launcher and power menu
- GTK application theme
- Font Awesome 7 icon font

## Three-panel Waybar

The status bar is split into three independent Waybar instances:

- **Top** — system info: clock, battery, network, volume
- **Right** — workspaces: 4 virtual desktops
- **Bottom** — controls: launcher, power menu, quick toggles

Each panel runs as a separate process, so a crash in one doesn't take down the others.`,
  },
  {
    id: 'usb-overlay',
    title: 'USB Boot & Overlay',
    icon: 'fa-solid fa-layer-group',
    content: `SuperLite is designed to run from a USB drive. The ISO boots directly into a live desktop environment without installation. For persistent storage, it uses an overlayfs setup that keeps RAM usage low.

## How it works

On first boot from USB, SuperLite checks for a writable partition labeled \`SUPERLITE-RW\`. If none exists, it creates one automatically using the remaining space on the USB drive. This ext4 partition becomes the writable layer of an overlayfs mount:

- **Lower layer** — read-only squashfs rootfs on the USB
- **Upper layer** — writable ext4 on the USB
- **Merged** — the filesystem the user sees

This means all user data, installed packages, and configuration changes persist across reboots — without loading everything into RAM.

## RAM usage

Without overlay, Alpine's live boot loads the entire rootfs into tmpfs. Chrome alone consumes 1GB+, leaving little room for actual work. With the USB overlay:

- Rootfs stays on USB (not in RAM)
- Only application memory uses RAM
- Typical usage: 1.4GB free out of 1.9GB total

## Fallback

If no USB partition is found (e.g., booting from a read-only medium), SuperLite falls back to tmpfs. Everything works, but changes don't persist and RAM is more constrained.`,
  },
  {
    id: 'installer',
    title: 'Offline Installer',
    icon: 'fa-solid fa-download',
    content: `SuperLite's installer went through three iterations before settling on its current form:

1. **Go** — first attempt. Too complex for the task, hard to maintain.
2. **Calamares** — the standard Linux installer. Removed from Alpine repos after v3.19.
3. **Python + tofi** — current. Simple, maintainable, fully offline.

## How it works

The installer uses Python for logic and tofi (a Wayland-native launcher) for the GUI. It presents a full-screen interface where the user selects a target disk, confirms the partition layout, and starts installation.

The actual installation is a tar pipe:

\`\`\`bash
tar -cf - -C / . | tar -xf - -C /mnt/target
\`\`\`

This copies the entire live system — packages, config, user files — directly to the target disk. No network required. No package downloads. No configuration wizards.

## Bootloader

GRUB is installed via chroot into the target system. If that fails (e.g., EFI variables not accessible), SuperLite falls back to a prebuilt bootloader copied from the USB drive.

## Partitioning

The installer uses sfdisk with proper GPT UUID strings. Alpine's sfdisk rejects type aliases like "UEFI" or "swap" — full UUID strings are required:

\`\`\`
type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B  # EFI System
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4  # Linux filesystem
type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F  # Linux swap
\`\`\``,
  },
];

export const Docs: FC = () => {
  const [active, setActive] = useState(SECTIONS[0].id);
  const [sidebarOpen, setSidebarOpen] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setActive(entry.target.id);
          }
        }
      },
      { rootMargin: '-20% 0px -60% 0px' }
    );

    SECTIONS.forEach(({ id }) => {
      const el = document.getElementById(id);
      if (el) observer.observe(el);
    });

    return () => observer.disconnect();
  }, []);

  const scrollTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
    setSidebarOpen(false);
  };

  return (
    <div className="docs">
      <button
        className="docs__mobile-toggle"
        onClick={() => setSidebarOpen((v) => !v)}
        aria-label="Toggle navigation"
      >
        <span /><span /><span />
      </button>

      <aside className={`docs__sidebar${sidebarOpen ? ' docs__sidebar--open' : ''}`}>
        <div className="docs__sidebar-header">
          <span className="docs__sidebar-title">Documentation</span>
        </div>
        <nav className="docs__nav">
          {SECTIONS.map((s) => (
            <button
              key={s.id}
              className={`docs__nav-item${active === s.id ? ' docs__nav-item--active' : ''}`}
              onClick={() => scrollTo(s.id)}
            >
              <i className={s.icon} />
              <span>{s.title}</span>
            </button>
          ))}
        </nav>
      </aside>

      <main className="docs__content">
        <header className="docs__hero">
          <span className="eyebrow"><i className="fa-solid fa-book-open" /> Documentation</span>
          <h1>SuperLite OS</h1>
          <p>A complete Linux desktop in 300MB. Alpine musl foundation with Debian glibc compatibility.</p>
        </header>

        {SECTIONS.map((s) => (
          <section key={s.id} id={s.id} className="docs__section">
            <h2 className="docs__section-title">{s.title}</h2>
            <div className="docs__section-body">
              {s.content.split('\n\n').map((block, i) => {
                if (block.startsWith('```')) {
                  const lines = block.split('\n');
                  const code = lines.slice(1, -1).join('\n');
                  return (
                    <pre key={i} className="docs__code">
                      <code>{code}</code>
                    </pre>
                  );
                }
                if (block.startsWith('| ')) {
                  const rows = block.split('\n').filter((r) => !r.match(/^\|[-\s|]+\|$/));
                  return (
                    <div key={i} className="docs__table-wrap">
                      <table className="docs__table">
                        <tbody>
                          {rows.map((row, ri) => (
                            <tr key={ri}>
                              {row.split('|').filter(Boolean).map((cell, ci) => (
                                ri === 0
                                  ? <th key={ci}>{cell.trim()}</th>
                                  : <td key={ci}>{cell.trim()}</td>
                              ))}
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  );
                }
                if (block.startsWith('- ')) {
                  return (
                    <ul key={i} className="docs__list">
                      {block.split('\n').map((li, li_i) => (
                        <li key={li_i}>{li.replace(/^- /, '').replace(/\*\*/g, '')}</li>
                      ))}
                    </ul>
                  );
                }
                if (block.startsWith('## ')) {
                  return <h3 key={i} className="docs__subheading">{block.replace('## ', '')}</h3>;
                }
                if (block.match(/^\d+\. /)) {
                  return (
                    <ol key={i} className="docs__olist">
                      {block.split('\n').map((li, li_i) => (
                        <li key={li_i}>{li.replace(/^\d+\. /, '').replace(/\*\*/g, '')}</li>
                      ))}
                    </ol>
                  );
                }
                return <p key={i} className="docs__para">{block}</p>;
              })}
            </div>
          </section>
        ))}
      </main>
    </div>
  );
};
