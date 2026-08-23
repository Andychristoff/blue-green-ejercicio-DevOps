import MenuItem from './MenuItem'

function MenuList({ items }) {
  if (items.length === 0) {
    return <p className="empty-state">No dishes match your search.</p>
  }

  const categories = [...new Set(items.map((item) => item.category))]

  return (
    <div className="menu-list">
      {categories.map((category) => (
        <section key={category} className="menu-category">
          <h2>{category}</h2>
          <ul>
            {items
              .filter((item) => item.category === category)
              .map((item) => (
                <MenuItem key={item.id} item={item} />
              ))}
          </ul>
        </section>
      ))}
    </div>
  )
}

export default MenuList
