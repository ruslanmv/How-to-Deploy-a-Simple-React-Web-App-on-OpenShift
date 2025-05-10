// src/App.js
import React from 'react';

function App() {
  return (
    <div style={{
      fontSize: '2rem',
      textAlign: 'center',
      padding: '2rem',
      fontFamily: 'sans-serif'
    }}>
      <h1>Hello, world!</h1>
      <p>Your React app is now running in OpenShift ROKS.</p>
    </div>
  );
}

export default App;