export function Input({
  label,
  type = 'text',
  className = '',
  error,
  value,
  onChange,
  ...props
}) {
  const isNumeric = type === 'number'
  const inputType = isNumeric ? 'text' : type
  const displayValue = isNumeric
    ? (value === '' || value == null ? '' : String(value))
    : value

  return (
    <div className="w-full">
      {label && (
        <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
          {label}
        </label>
      )}
      <input
        type={inputType}
        inputMode={isNumeric ? 'decimal' : undefined}
        className={
          'w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100 dark:placeholder-gray-400 ' +
          (error ? 'border-danger ' : '') +
          className
        }
        value={displayValue}
        onChange={onChange}
        {...props}
      />
      {error && <p className="mt-1 text-sm text-danger">{error}</p>}
    </div>
  )
}
