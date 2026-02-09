export function Input({
  label,
  type = 'text',
  className = '',
  error,
  ...props
}) {
  return (
    <div className="w-full">
      {label && (
        <label className="mb-1 block text-sm font-medium text-gray-700">
          {label}
        </label>
      )}
      <input
        type={type}
        className={
          'w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none ' +
          (error ? 'border-danger ' : '') +
          className
        }
        {...props}
      />
      {error && <p className="mt-1 text-sm text-danger">{error}</p>}
    </div>
  )
}
