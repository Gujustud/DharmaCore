const statusColors = {
  draft: 'bg-gray-200 text-gray-800 dark:bg-gray-600 dark:text-white',
  sent: 'bg-blue-100 text-blue-800 dark:bg-blue-600 dark:text-white',
  won: 'bg-success/20 text-success dark:bg-green-600 dark:text-white',
  lost: 'bg-gray-300 text-gray-600 dark:bg-gray-500 dark:text-white',
  planning: 'bg-blue-100 text-blue-800 dark:bg-blue-600 dark:text-white',
  in_progress: 'bg-warning/20 text-amber-700 dark:bg-amber-600 dark:text-white',
  done: 'bg-success/20 text-success dark:bg-green-600 dark:text-white',
  cancelled: 'bg-gray-300 text-gray-600 dark:bg-gray-500 dark:text-white',
  not_shipped: 'bg-gray-200 text-gray-700 dark:bg-gray-500 dark:text-white',
  in_transit: 'bg-blue-100 text-blue-800 dark:bg-blue-600 dark:text-white',
  delivered: 'bg-success/20 text-success dark:bg-green-600 dark:text-white',
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
