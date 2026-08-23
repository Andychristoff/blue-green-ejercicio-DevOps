function SearchBar({ value, onChange }) {
  return (
    <div className="search-bar">
      <input
        type="text"
        placeholder="Search the menu..."
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-label="Search menu items"
      />
      {value && (
        <button
          className="clear-button"
          onClick={() => onChange('')}
          aria-label="Clear search"
        >
          ×
        </button>
      )}
    </div>
  )
}

export default SearchBar
