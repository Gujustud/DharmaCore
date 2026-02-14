export function Button({
  children,
  variant = 'primary',
  type = 'button',
  className = '',
  disabled,
  ...props
}) {
  const base =
    'rounded-button px-4 py-2 font-medium transition focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:opacity-50 '
  const variants = {
    primary:
      'bg-gradient-to-r from-primary-from to-primary-to text-white hover:opacity-90 focus:ring-primary-from dark:focus:ring-offset-gray-800',
    secondary:
      'bg-gray-200 text-gray-800 hover:bg-gray-300 focus:ring-gray-400 dark:bg-gray-500 dark:text-white dark:border dark:border-gray-400 dark:hover:bg-gray-400 dark:hover:border-gray-300 dark:focus:ring-offset-gray-800',
    danger: 'bg-danger text-white hover:bg-red-700 focus:ring-danger dark:focus:ring-offset-gray-800',
    ghost:
      'bg-transparent text-gray-700 hover:bg-gray-100 focus:ring-gray-300 dark:text-gray-200 dark:hover:bg-gray-600 dark:focus:ring-offset-gray-800',
  }
  return (
    <button
      type={type}
      className={base + (variants[variant] || variants.primary) + ' ' + className}
      disabled={disabled}
      data-variant={variant}
      {...props}
    >
      {children}
    </button>
  )
}
