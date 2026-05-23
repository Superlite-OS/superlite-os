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
  shortcuts: Shortcut[];
}

const GROUPS: ShortcutGroup[] = [
  {
    title: 'Window Management',
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
    shortcuts: [
      { keys: ['Super', '1–4'], label: 'Switch workspace' },
      { keys: ['Super', 'Shift', '1–4'], label: 'Move to workspace' },
      { keys: ['Super', 'Tab'], label: 'Next window' },
      { keys: ['Super', 'Shift', 'Tab'], label: 'Previous window' },
    ],
  },
  {
    title: 'System',
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
  <>
    <PageHero eyebrow="Keyboard Shortcuts" subtitle="Window management, workspaces, and system controls at your fingertips.">
      Productivity built in.
    </PageHero>

    <section className="section">
      <div className="container">
        <div className="sc__grid">
          {GROUPS.map((group, gi) => (
            <Reveal key={group.title} delay={gi * 100}>
              <div className="sc__group">
                <h3 className="sc__group-title">{group.title}</h3>
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
  </>
);
