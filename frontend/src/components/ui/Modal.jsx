export function Modal({ open, onClose, title, children }) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div
        className="absolute inset-0 bg-black/50"
        onClick={onClose}
        aria-hidden
      />
      <div className="relative z-10 max-h-[90vh] w-full max-w-lg overflow-auto rounded-card bg-white p-6 shadow-lg">
        {title && (
          <h2 className="mb-4 text-lg font-bold text-gray-900">{title}</h2>
        )}
        {children}
      </div>
    </div>
  )
}
