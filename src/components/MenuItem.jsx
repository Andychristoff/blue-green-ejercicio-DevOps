import { useState } from 'react'

function MenuItem({ item }) {
  const [status, setStatus] = useState('idle')

  async function order() {
    setStatus('sending')
    try {
      const res = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ product: item.name }),
      })
      setStatus(res.ok ? 'done' : 'error')
    } catch {
      setStatus('error')
    }
    setTimeout(() => setStatus('idle'), 1500)
  }

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
        <button
          type="button"
          className="order-button"
          onClick={order}
          disabled={status === 'sending'}
        >
          {status === 'done' ? '✓ Ordered' : status === 'error' ? 'Error, retry' : 'Order'}
        </button>
      </div>
    </li>
  )
}

export default MenuItem
