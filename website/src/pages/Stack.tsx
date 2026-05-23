import type { FC } from 'react';
import { PageHero } from '../components/PageHero';
import { Reveal } from '../components/Reveal';
import './Stack.css';

const STACK = [
  { name: 'Alpine Linux', role: 'Base system · musl libc', icon: 'fa-brands fa-linux' },
  { name: 'LabWC', role: 'Wayland compositor · OpenBox-style', icon: 'fa-solid fa-window-maximize' },
  { name: 'Waybar', role: '3-panel layout · sway/workspaces', icon: 'fa-solid fa-bars-staggered' },
  { name: 'Foot', role: 'Wayland terminal', icon: 'fa-solid fa-terminal' },
  { name: 'Mako', role: 'Notification daemon', icon: 'fa-solid fa-bell' },
  { name: 'tofi', role: 'Full-screen app launcher', icon: 'fa-solid fa-magnifying-glass' },
  { name: 'Double Commander', role: 'Dual pane file manager · via zapt', icon: 'fa-solid fa-folder-tree' },
  { name: 'PipeWire', role: 'Audio stack', icon: 'fa-solid fa-volume-high' },
  { name: 'Google Chrome', role: 'Browser · glibc sandbox', icon: 'fa-brands fa-chrome' },
  { name: 'zapt', role: '.deb package manager · glibc isolation', icon: 'fa-solid fa-box-archive' },
  { name: 'Catppuccin Mocha', role: 'Unified dark theme', icon: 'fa-solid fa-palette' },
  { name: 'Font Awesome 7', role: 'Icon font for waybar', icon: 'fa-solid fa-icons' },
] as const;

export const Stack: FC = () => (
  <div className="page-enter">
    <PageHero eyebrow={<><i className="fa-solid fa-layer-group" /> Desktop Stack</>} subtitle="Each component tested and chosen. Nothing here by accident.">
      Curated components.
    </PageHero>

    <section className="section">
      <div className="container">
        <div className="stack__grid">
          {STACK.map((item, i) => (
            <Reveal key={item.name} delay={i * 60}>
              <div className="stack__card card-hover spin-hover">
                <i className={`stack__icon ${item.icon}`} />
                <div className="stack__name">{item.name}</div>
                <div className="stack__role">{item.role}</div>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  </div>
);
