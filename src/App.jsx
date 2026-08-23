import { useMemo, useState } from 'react'
import SearchBar from './components/SearchBar'
import MenuList from './components/MenuList'
import menu from './data/menu'
import './App.css'

const APP_VERSION = import.meta.env.VITE_APP_VERSION || '1.0.0'

function App() {
  const [query, setQuery] = useState('')

  const filteredItems = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return menu
    return menu.filter(
      (item) =>
        item.name.toLowerCase().includes(q) ||
        item.description.toLowerCase().includes(q) ||
        item.category.toLowerCase().includes(q),
    )
  }, [query])

  return (
    <div className="app">
      <header className="app-header">
        <h1>🍽️ Blue Plate Diner</h1>
        <p className="tagline">Today's menu</p>
      </header>

      <main>
        <SearchBar value={query} onChange={setQuery} />
        <MenuList items={filteredItems} />
      </main>

      <footer className="app-footer">
        <span>v{APP_VERSION}</span>
      </footer>
    </div>
  )
}

export default App
