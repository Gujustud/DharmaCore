import PocketBase from 'pocketbase'

export const pb = new PocketBase(import.meta.env.VITE_POCKETBASE_URL || 'http://127.0.0.1:8090')

// Prevent "request was autocancelled" when React Strict Mode runs effects twice
pb.autoCancellation(false)
