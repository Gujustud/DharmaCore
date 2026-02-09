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
      'bg-gradient-to-r from-primary-from to-primary-to text-white hover:opacity-90 focus:ring-primary-from',
    secondary: 'bg-gray-200 text-gray-800 hover:bg-gray-300 focus:ring-gray-400',
    danger: 'bg-danger text-white hover:bg-red-700 focus:ring-danger',
    ghost: 'bg-transparent hover:bg-gray-100 focus:ring-gray-300',
  }
  return (
    <button
      type={type}
      className={base + (variants[variant] || variants.primary) + ' ' + className}
      disabled={disabled}
      {...props}
    >
      {children}
    </button>
  )
}
