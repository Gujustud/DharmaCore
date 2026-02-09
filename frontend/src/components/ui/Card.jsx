export function Card({ children, className = '' }) {
  return (
    <div
      className={
        'rounded-card bg-white p-4 shadow-card ' + className
      }
    >
      {children}
    </div>
  )
}
