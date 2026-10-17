import React, { useEffect, useState } from 'react'

// Small on purpose. It exists so that "the page loads" and "the API answers"
// are two different failures, which is what several of the challenges turn on.
export default function App() {
  const [health, setHealth] = useState('checking…')
  const [rows, setRows] = useState([])
  const [error, setError] = useState('')

  useEffect(() => {
    fetch('/api/health/')
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error('HTTP ' + r.status))))
      .then((d) => setHealth(d.status + ' (' + d.env + ')'))
      .catch((e) => { setHealth('unreachable'); setError(String(e.message)) })

    fetch('/api/placements/?limit=20')
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error('HTTP ' + r.status))))
      .then(setRows)
      .catch((e) => setError(String(e.message)))
  }, [])

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', margin: '2rem', maxWidth: '48rem' }}>
      <p style={{ background: '#fff4d6', padding: '0.75rem', border: '1px solid #e0c060' }}>
        <strong>Stand-in app.</strong> Invented data only. This is not the real
        internship-management application.
      </p>
      <h1>Placements</h1>
      <p>API: <strong>{health}</strong></p>
      {error && <p style={{ color: '#a00' }}>Last error: {error}</p>}
      <table cellPadding="6" style={{ borderCollapse: 'collapse' }}>
        <thead>
          <tr><th align="left">Ward</th><th align="left">Started</th><th align="left">Status</th></tr>
        </thead>
        <tbody>
          {rows.map((p) => (
            <tr key={p.id}>
              <td>{p.ward}</td><td>{p.started_on}</td><td>{p.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {rows.length === 0 && <p>No placements returned.</p>}
    </main>
  )
}
