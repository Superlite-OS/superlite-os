import type { FC } from 'react';
import { PageHero } from '../components/PageHero';
import { Reveal } from '../components/Reveal';
import './Stack.css';

const STACK = [
  { name: 'Alpine Linux', role: 'Base system · musl libc' },
  { name: 'LabWC', role: 'Wayland compositor · OpenBox-style' },
  { name: 'Waybar', role: '3-panel layout · sway/workspaces' },
  { name: 'Foot', role: 'Wayland terminal' },
  { name: 'Mako', role: 'Notification daemon' },
  { name: 'tofi', role: 'Full-screen app launcher' },
  { name: 'Double Commander', role: 'File manager · via zapt' },
  { name: 'PipeWire', role: 'Audio stack' },
  { name: 'Google Chrome', role: 'Browser · glibc sandbox' },
  { name: 'zapt', role: '.deb package manager · glibc isolation' },
  { name: 'Catppuccin Mocha', role: 'Unified dark theme' },
  { name: 'Font Awesome 7', role: 'Icon font for waybar' },
] as const;

export const Stack: FC = () => (
  <>
    <PageHero eyebrow="Desktop Stack" subtitle="Every component earned its place. Tested, questioned, replaced if something better existed.">
      Curated components.
    </PageHero>

    <section className="section">
      <div className="container">
        <div className="stack__grid">
          {STACK.map((item, i) => (
            <Reveal key={item.name} delay={i * 60}>
              <div className="stack__card">
                <div className="stack__name">{item.name}</div>
                <div className="stack__role">{item.role}</div>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  </>
);
