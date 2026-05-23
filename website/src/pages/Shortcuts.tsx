import type { FC } from 'react';
import { PageHero } from '../components/PageHero';
import { Reveal } from '../components/Reveal';
import './Shortcuts.css';

interface Shortcut {
  keys: string[];
  label: string;
}

interface ShortcutGroup {
  title: string;
  icon: string;
  shortcuts: Shortcut[];
}

const GROUPS: (ShortcutGroup & { icon: string })[] = [
  {
    title: 'Window Management',
    icon: 'fa-solid fa-window-maximize',
    shortcuts: [
      { keys: ['Super', 'M'], label: 'Maximize / Restore' },
      { keys: ['Super', 'N'], label: 'Minimize' },
      { keys: ['Super', 'F'], label: 'Fullscreen' },
      { keys: ['Super', 'Shift', 'Q'], label: 'Close window' },
      { keys: ['Super', 'T'], label: 'Always on top' },
    ],
  },
  {
    title: 'Window Snapping',
    icon: 'fa-solid fa-table-columns',
    shortcuts: [
      { keys: ['Super', '←'], label: 'Snap left' },
      { keys: ['Super', '→'], label: 'Snap right' },
      { keys: ['Super', '↑'], label: 'Snap top' },
      { keys: ['Super', '↓'], label: 'Snap bottom' },
      { keys: ['Super', 'Shift', 'C'], label: 'Snap center (66%)' },
    ],
  },
  {
    title: 'Workspaces',
    icon: 'fa-solid fa-th',
    shortcuts: [
      { keys: ['Super', '1–4'], label: 'Switch workspace' },
      { keys: ['Super', 'Shift', '1–4'], label: 'Move to workspace' },
      { keys: ['Super', 'Tab'], label: 'Next window' },
      { keys: ['Super', 'Shift', 'Tab'], label: 'Previous window' },
    ],
  },
  {
    title: 'System',
    icon: 'fa-solid fa-gear',
    shortcuts: [
      { keys: ['Super', 'Enter'], label: 'Terminal (foot)' },
      { keys: ['Super', 'Space'], label: 'App launcher (tofi)' },
      { keys: ['Super', 'P'], label: 'Screenshot' },
      { keys: ['Super', 'Shift', 'E'], label: 'Power menu' },
    ],
  },
];

const KeyCombo: FC<{ keys: string[] }> = ({ keys }) => (
  <span className="sc__keys">
    {keys.map((k, i) => (
      <span key={i}>
        <kbd className="sc__kbd">{k}</kbd>
        {i < keys.length - 1 && <span className="sc__plus">+</span>}
      </span>
    ))}
  </span>
);

export const Shortcuts: FC = () => (
  <div className="page-enter">
    <PageHero eyebrow={<><i className="fa-solid fa-keyboard" /> Keyboard Shortcuts</>} subtitle="Window management, workspaces, and system controls.">
      Productivity built in.
    </PageHero>

    <section className="section">
      <div className="container">
        <div className="sc__grid">
          {GROUPS.map((group, gi) => (
            <Reveal key={group.title} delay={gi * 100}>
              <div className="sc__group card-hover">
                <h3 className="sc__group-title"><i className={group.icon} /> {group.title}</h3>
                <div className="sc__list">
                  {group.shortcuts.map((s) => (
                    <div key={s.label} className="sc__item">
                      <KeyCombo keys={s.keys} />
                      <span className="sc__label">{s.label}</span>
                    </div>
                  ))}
                </div>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  </div>
);
