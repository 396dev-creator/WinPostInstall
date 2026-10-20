/**
 * Script to replace hardcoded hex colors with CSS variable references
 * across all WinPostInstall component files, enabling proper dark/light theming.
 */
const fs = require('fs');
const path = require('path');

const COMPONENTS_DIR = path.join(__dirname, '..', 'src', 'components', 'winpost');
const APP_DIR = path.join(__dirname, '..', 'src', 'app');

// Files to process
const filesToProcess = [
  path.join(COMPONENTS_DIR, 'AppHeader.tsx'),
  path.join(COMPONENTS_DIR, 'DashboardTab.tsx'),
  path.join(COMPONENTS_DIR, 'QuickSelectBar.tsx'),
  path.join(COMPONENTS_DIR, 'SafetyBadge.tsx'),
  path.join(COMPONENTS_DIR, 'SectionDetailPanel.tsx'),
  path.join(COMPONENTS_DIR, 'SoftwareInstallTab.tsx'),
  path.join(COMPONENTS_DIR, 'ProfilesTab.tsx'),
  path.join(COMPONENTS_DIR, 'ProfileComparison.tsx'),
  path.join(COMPONENTS_DIR, 'PreviewTab.tsx'),
  path.join(COMPONENTS_DIR, 'UndoCenterTab.tsx'),
  path.join(COMPONENTS_DIR, 'RegistryScanTab.tsx'),
  path.join(COMPONENTS_DIR, 'ISOBuilderTab.tsx'),
  path.join(APP_DIR, 'page.tsx'),
];

// Color mappings: hardcoded hex → CSS variable name
// We replace [#hex] with [var(--wpi-xxx)] in Tailwind classes
const colorMap = {
  // UI chrome colors (change between themes)
  '#0a0a0f': 'var(--wpi-bg)',       // Main background
  '#0d0d14': 'var(--wpi-bg-deep)', // Slightly different bg (filter bar)
  '#12121a': 'var(--wpi-deep)',     // Deep card / input bg
  '#1a1a2e': 'var(--wpi-card)',     // Card background
  '#2a2a3e': 'var(--wpi-border)',   // Border color
  '#00d4ff': 'var(--wpi-accent)',   // Cyan accent
  '#e0e0e0': 'var(--wpi-text)',     // Primary text
  '#8888a0': 'var(--wpi-muted)',   // Muted text
  '#0ea5e9': 'var(--wpi-info)',     // Info blue
};

// Sort keys longest first to avoid partial matches (e.g., #0a0a0f before #0a0a)
const sortedKeys = Object.keys(colorMap).sort((a, b) => b.length - a.length);

let totalReplacements = 0;

filesToProcess.forEach(filePath => {
  if (!fs.existsSync(filePath)) {
    console.log(`SKIP: ${path.basename(filePath)} not found`);
    return;
  }

  let content = fs.readFileSync(filePath, 'utf8');
  let fileReplacements = 0;

  sortedKeys.forEach(hex => {
    const varRef = colorMap[hex];
    // Replace [#hex] with [var(--wpi-xxx)] in Tailwind arbitrary values
    // This handles: bg-[#hex], text-[#hex], border-[#hex], etc.
    const pattern = new RegExp(`\\[${hex}\\]`, 'g');
    const matches = content.match(pattern);
    if (matches) {
      content = content.replace(pattern, `[${varRef}]`);
      fileReplacements += matches.length;
    }
  });

  if (fileReplacements > 0) {
    fs.writeFileSync(filePath, content, 'utf8');
    console.log(`✓ ${path.basename(filePath)}: ${fileReplacements} replacements`);
    totalReplacements += fileReplacements;
  } else {
    console.log(`- ${path.basename(filePath)}: no changes`);
  }
});

console.log(`\nTotal replacements: ${totalReplacements}`);
