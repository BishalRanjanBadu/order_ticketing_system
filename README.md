Cakes & Bakes — Ticket Rail

Order intake for two retail shops, syncing into one factory production
dashboard — with a live catalog, a separate custom-cake flow, Google-only
sign-in, owner-level user management, role-locked views, an audit trail,
session undo/redo, and Excel/CSV exports. Single HTML file, mobile-friendly,
backed by your own free Supabase project.

---

## 🚀 Key Features

*   **Dual-Outlet Order Intake:** Seamlessly switch modes to log standard catalog items or build highly-detailed custom cake requests.
*   **Centralized Production Rail:** An interactive, drag-and-drop styled Kanban-board status tracker (`New` ➔ `Confirmed` ➔ `Baking` ➔ `Ready` ➔ `Delivered`) to keep the kitchen synchronized.
*   **Secure Google OAuth Integration:** Restricted enterprise login using Google Accounts to manage factory staff, shop managers, and administrative roles.
*   **Real-time Synchronization:** Subscribes directly to Supabase Database changes to instantly reflect order status updates across all open screens without page reloads.
*   **Media Support:** Integrates with Supabase Storage to allow shop staff to upload reference photos for custom cake designs.
*   **Audit Trail:** Built-in history logs detailing precisely who modified an order and when.
*   **Data Portability:** One-click export feature generating clean Excel (`.xlsx`) or CSV files for sales reconciliation and production forecasting.

---

## 🛠️ System Architecture & Tech Stack

*   **Frontend:** Vanilla JS (ES6+), Google Fonts (Fraunces & Inter), XLSX.js (for client-side spreadsheet generation).
*   **Database & Auth:** [Supabase](https://supabase.com) (PostgreSQL, Realtime, GoTrue Auth, and Storage Buckets).
*   **Hosting:** Fully compatible with [GitHub Pages](https://pages.github.com/) or any static file hosting service.

---

## 🏁 Quick Start Setup Guide

### 1. Supabase Backend Setup
1. Create a new, free project on the [Supabase Dashboard](https://supabase.com/dashboard).
2. Navigate to the **SQL Editor** in your Supabase project, create a **New Query**, and execute your database schema (including the `orders`, `profiles`, `shops`, and `catalog` tables).
3. Go to **Storage**, create a new public bucket named `cake-references` to allow reference image uploads.
4. Go to **Authentication** ➔ **Providers** ➔ **Google**:
   * Enable Google Sign-In.
   * Copy your Google Cloud **Client ID** and **Client Secret** (obtained from your Google Cloud Console project).
   * Copy the **Redirect URI** provided by Supabase and save it in your Google Cloud OAuth credentials.

### 2. GitHub Pages Deployment
1. Push `index.html` directly to the root folder of your GitHub repository.
2. In your repository on GitHub, go to **Settings** ➔ **Pages**.
3. Under **Build and deployment**, set the source to deploy from the `main` branch.
4. Once deployed, open your live URL (e.g., `https://<your-username>.github.io/<your-repo-name>/`).
5. On the first load, the app will prompt you to securely enter your **Supabase Project URL** and **Anon Key** (found under **Settings** ➔ **API** in your Supabase dashboard) to permanently link your frontend to your backend.

---

## 🔒 Security & Roles

The system supports granular user permission mapping stored securely in PostgreSQL:
*   **Admin:** Complete access to catalog settings, system variables, user mapping, and exports.
*   **Baker / Kitchen Staff:** View-only access to the active baking queue, with permissions to progress tickets through production stages.
*   **Shop Staff:** Restricted access to submit new orders and monitor delivery statuses for their respective outlets.

---

