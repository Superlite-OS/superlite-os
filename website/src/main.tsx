import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter, Routes, Route } from 'react-router-dom';
import { Nav } from './components/Nav';
import { Footer } from './components/Footer';
import { Home } from './pages/Home';
import { Features } from './pages/Features';
import { Stack } from './pages/Stack';
import { Shortcuts } from './pages/Shortcuts';
import { Build } from './pages/Build';
import './styles/global.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <HashRouter>
      <Nav />
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/features" element={<Features />} />
        <Route path="/stack" element={<Stack />} />
        <Route path="/shortcuts" element={<Shortcuts />} />
        <Route path="/build" element={<Build />} />
      </Routes>
      <Footer />
    </HashRouter>
  </StrictMode>,
);
