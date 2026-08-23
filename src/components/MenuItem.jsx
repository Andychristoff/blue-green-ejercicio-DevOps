function MenuItem({ item }) {
  return (
    <li className="menu-item">
      <span className="menu-item-emoji" aria-hidden="true">
        {item.emoji}
      </span>
      <div className="menu-item-body">
        <div className="menu-item-header">
          <h3>{item.name}</h3>
          <span className="menu-item-price">${item.price.toFixed(2)}</span>
        </div>
        <p className="menu-item-description">{item.description}</p>
      </div>
    </li>
  )
}

export default MenuItem
