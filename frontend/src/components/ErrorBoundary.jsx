import { Component } from 'react'

export class ErrorBoundary extends Component {
  state = { error: null }

  static getDerivedStateFromError(error) {
    return { error }
  }

  componentDidCatch(error, info) {
    console.error('App error:', error, info)
  }

  render() {
    if (this.state.error) {
      return (
        <div className="max-w-[600px] p-6 font-sans text-gray-900 dark:text-gray-100">
          <h1 className="text-red-600 dark:text-red-400">Something went wrong</h1>
          <pre className="mt-2 overflow-auto rounded-lg bg-gray-100 p-4 text-sm dark:bg-gray-800 dark:text-gray-200">
            {this.state.error?.message ?? String(this.state.error)}
          </pre>
          <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
            Open the browser console (F12) for more details.
          </p>
        </div>
      )
    }
    return this.props.children
  }
}
