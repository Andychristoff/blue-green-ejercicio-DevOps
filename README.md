# Blue Plate Diner

A tiny React + Vite web app: a restaurant menu with prices and a search bar
that filters dishes by name, description, or category. Built as a simple
target app for practicing blue/green deployments.

## Run locally

```bash
npm install
npm run dev
```

Open the URL Vite prints (defaults to http://localhost:5173/).

## Build for production

```bash
npm run build
npm run preview
```

## Structure

- `src/data/menu.js` — the menu items (name, category, description, price).
  Edit prices here for a minimal "green" version to deploy alongside "blue".
- `src/components/` — `SearchBar`, `MenuList`, `MenuItem`.
- `src/App.jsx` — wires search state to the filtered menu list.

The footer shows a version string (`v1.0.0` by default), overridable via the
`VITE_APP_VERSION` environment variable — handy for telling the blue and
green deployments apart at a glance.
