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
        <div style={{ padding: 24, fontFamily: 'sans-serif', maxWidth: 600 }}>
          <h1 style={{ color: '#dc2626' }}>Something went wrong</h1>
          <pre style={{ background: '#f3f4f6', padding: 16, overflow: 'auto' }}>
            {this.state.error?.message ?? String(this.state.error)}
          </pre>
          <p style={{ color: '#6b7280' }}>
            Open the browser console (F12) for more details.
          </p>
        </div>
      )
    }
    return this.props.children
  }
}
