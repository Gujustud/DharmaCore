# DharmaCore - CNC Quote Tracker

A comprehensive web application for managing CNC machining quotes, jobs, customers, and vendors. Built with React, PocketBase, and Tailwind CSS.

## Overview

DharmaCore is a full-featured quote and job tracking system designed specifically for CNC machining shops. It helps you manage the entire workflow from initial quotes through job completion, including customer management, vendor tracking, material costing, and project documentation.

## Features

### Quote Management
- Create and manage detailed quotes with multiple line items
- Calculate material costs, tooling, labor, and subcontractor expenses
- Support for USD/CAD exchange rates with auto-update capability
- Customizable markup percentages (shipping, final, subcontractor)
- Track quote status: Draft, Sent, Won, Lost
- Copy quotes for quick iteration
- Visual part images for quick reference

### Job Tracking
- Automatically create jobs from won quotes
- Track job status: Planning, In Progress, Done, Cancelled
- Manage shipping and tracking information
- Track completion dates and ship dates
- Material lot tracking and sourcing
- Project notes and documentation
- Visual part images with hover-to-view full-size

### Customer & Vendor Management
- Centralized customer database with contact information
- Vendor management for material suppliers and subcontractors
- Quick customer creation from quote/job pages

### Dashboard & Analytics
- Monthly quote statistics
- Win rate tracking
- Revenue tracking for won quotes
- Active jobs overview
- Recent quotes list

### User Interface
- **Dark mode** – Toggle in Settings → Appearance; applies immediately across the app (cards, tables, forms, buttons, status badges)
- Sticky sidebar on Quote detail: Quote Totals and Settings stay visible while scrolling line items

### Security & Session Management
- User authentication system
- Auto-logout after configurable inactivity period
- Protected routes requiring authentication

### Part Images
- Upload or paste images directly into quotes and jobs
- Thumbnail gallery view (300x300)
- Hover to view full-size images
- Multiple images per quote/job (up to 10)

## Tech Stack

- **Frontend**: React 18, React Router, Vite
- **Backend**: PocketBase (Go-based backend with SQLite)
- **Styling**: Tailwind CSS
- **Date Handling**: date-fns

## Getting Started

### Prerequisites

- Node.js (v18 or higher)
- PocketBase executable (included in backend folder)

### Installation

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd DharmaCore
   ```

2. **Install frontend dependencies**
   ```bash
   cd frontend
   npm install
   ```

3. **Start PocketBase backend**
   ```bash
   cd backend
   ./pocketbase.exe serve
   ```
   (or `pocketbase serve` on Mac/Linux)
   
   PocketBase will automatically run migrations on first start, creating all necessary collections and fields.

4. **Start the frontend development server**
   ```bash
   cd frontend
   npm run dev
   ```

5. **Access the application**
   - Frontend: http://localhost:5173 (or the port shown in terminal)
   - PocketBase Admin: http://localhost:8090/_/ (for database management)

### Initial Setup

1. **Create your first user**
   - Go to PocketBase Admin UI (http://localhost:8090/_/)
   - Navigate to Collections → users
   - Create a new user with email and password

2. **Configure settings**
   - Log into the app
   - Go to Settings page
   - Configure default markups, exchange rates, and hourly rates
   - Set auto-logout timeout if desired

3. **Add customers and vendors**
   - Use the Customers and Vendors pages to add your contacts

## Project Structure

```
DharmaCore/
├── backend/
│   ├── pb_migrations/     # Database migrations
│   ├── pb_data/           # Database files (excluded from git)
│   └── pocketbase.exe     # PocketBase executable (excluded from git)
├── frontend/
│   ├── src/
│   │   ├── components/    # React components
│   │   ├── pages/         # Page components
│   │   └── lib/           # Utilities and API client
│   └── package.json
└── README.md
```

## Database Migrations

The app uses PocketBase migrations to manage schema changes. Migrations are automatically applied when PocketBase starts. See `backend/README_MIGRATIONS.md` for details on creating new migrations.

## Key Features Explained

### Quote Calculations
- Material costs can be entered in USD or CAD
- Automatic exchange rate conversion
- Labor costs calculated from hourly rates × hours
- Markups applied at multiple levels (shipping, final, subcontractor)
- Line-by-line totals and quote-level totals

### Job Creation
- Jobs are automatically created when a quote is marked "Won"
- Job inherits quote information (customer, job number, parts description)
- Can be created manually if needed (quote optional)

### Tracking Links
- Tracking numbers on jobs generate carrier-specific links (FedEx, UPS, Canada Post, Purolator, DHL Express)
- DHL Express uses MyDHL format: `https://mydhl.express.dhl/ca/en/tracking.html#/results?id=...`

### Part Images
- Upload images via file picker or paste from clipboard
- Images stored in PocketBase file storage
- Thumbnails generated automatically (300x300)
- Full-size images viewable on hover

## Development

### Running in Development Mode

1. Start PocketBase: `cd backend && ./pocketbase.exe serve`
2. Start Frontend: `cd frontend && npm run dev`

### Building for Production

```bash
cd frontend
npm run build
```

The built files will be in `frontend/dist/`.

## Configuration

### Environment Variables

Create a `.env` file in the `frontend` directory:

```
VITE_POCKETBASE_URL=http://127.0.0.1:8090
```

### PocketBase Configuration

- Default URL: http://127.0.0.1:8090
- Database: SQLite (stored in `backend/pb_data/data.db`)
- File storage: Local filesystem (stored in `backend/pb_data/storage/`)

## License

[Your License Here]

## Support

[Your Support Information Here]
