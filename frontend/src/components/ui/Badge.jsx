const statusColors = {
  draft: 'bg-gray-200 text-gray-800',
  sent: 'bg-blue-100 text-blue-800',
  won: 'bg-success/20 text-success',
  lost: 'bg-gray-300 text-gray-600',
  planning: 'bg-blue-100 text-blue-800',
  in_progress: 'bg-warning/20 text-amber-700',
  done: 'bg-success/20 text-success',
  cancelled: 'bg-gray-300 text-gray-600',
  not_shipped: 'bg-gray-200 text-gray-700',
  in_transit: 'bg-blue-100 text-blue-800',
  delivered: 'bg-success/20 text-success',
}

export function Badge({ children, status, className = '' }) {
  const color = statusColors[status] || 'bg-gray-200 text-gray-800'
  return (
    <span
      className={
        'inline-flex rounded-full px-2 py-0.5 text-xs font-medium ' +
        color +
        ' ' +
        className
      }
    >
      {children}
    </span>
  )
}
