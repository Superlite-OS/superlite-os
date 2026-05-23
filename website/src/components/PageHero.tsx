import type { FC, ReactNode } from 'react';
import './PageHero.css';

interface PageHeroProps {
  eyebrow: string;
  children: ReactNode;
  subtitle?: string;
}

export const PageHero: FC<PageHeroProps> = ({ eyebrow, children, subtitle }) => (
  <header className="page-hero">
    <div className="page-hero__bg" />
    <div className="page-hero__content">
      <span className="page-hero__eyebrow">{eyebrow}</span>
      <h1 className="page-hero__title">{children}</h1>
      {subtitle && <p className="page-hero__sub">{subtitle}</p>}
    </div>
  </header>
);
