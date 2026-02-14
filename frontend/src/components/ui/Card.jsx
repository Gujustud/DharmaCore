export function Card({ children, className = '' }) {
  return (
    <div
      className={
        'rounded-card bg-white p-4 shadow-card dark:bg-gray-800 dark:shadow-none dark:ring-1 dark:ring-gray-700 ' + className
      }
    >
      {children}
    </div>
  )
}
