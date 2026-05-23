import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter, Routes, Route } from 'react-router-dom';
import { Nav } from './components/Nav';
import { Footer } from './components/Footer';
import { BgLayer } from './components/BgLayer';
import { Home } from './pages/Home';
import { Features } from './pages/Features';
import { Stack } from './pages/Stack';
import { Shortcuts } from './pages/Shortcuts';
import { Build } from './pages/Build';
import { Docs } from './pages/Docs';
import './styles/global.css';
import './styles/animations.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <HashRouter>
      <BgLayer />
      <Nav />
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/features" element={<Features />} />
        <Route path="/stack" element={<Stack />} />
        <Route path="/shortcuts" element={<Shortcuts />} />
        <Route path="/build" element={<Build />} />
        <Route path="/docs" element={<Docs />} />
      </Routes>
      <Footer />
    </HashRouter>
  </StrictMode>,
);
