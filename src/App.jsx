import { useMemo, useState } from 'react'
import SearchBar from './components/SearchBar'
import MenuList from './components/MenuList'
import menu from './data/menu'
import './App.css'

const APP_VERSION = import.meta.env.VITE_APP_VERSION || '1.0.0'
const DEPLOY_COLOR = /blue/i.test(APP_VERSION)
  ? 'blue'
  : /green/i.test(APP_VERSION)
    ? 'green'
    : 'neutral'

function App() {
  const [query, setQuery] = useState('')
  const [sortByPrice, setSortByPrice] = useState(false)

  const filteredItems = useMemo(() => {
    const q = query.trim().toLowerCase()
    const base = !q
      ? menu
      : menu.filter(
          (item) =>
            item.name.toLowerCase().includes(q) ||
            item.description.toLowerCase().includes(q) ||
            item.category.toLowerCase().includes(q),
        )
    return sortByPrice ? [...base].sort((a, b) => a.price - b.price) : base
  }, [query, sortByPrice])

  return (
    <div className={`app app--${DEPLOY_COLOR}`}>
      <header className="app-header">
        <h1>🍽️ Blue Plate Diner</h1>
        <p className="tagline">Today's menu</p>
      </header>

      <main>
        <SearchBar value={query} onChange={setQuery} />

        <div className="menu-toolbar">
          <span className="result-count">
            {filteredItems.length} {filteredItems.length === 1 ? 'dish' : 'dishes'}
          </span>
          <label className="sort-toggle">
            <input
              type="checkbox"
              checked={sortByPrice}
              onChange={(e) => setSortByPrice(e.target.checked)}
            />
            Sort by price
          </label>
        </div>

        <MenuList items={filteredItems} grouped={!sortByPrice} />
      </main>

      <footer className="app-footer">
        <span>v{APP_VERSION}</span>
      </footer>
    </div>
  )
}

export default App
