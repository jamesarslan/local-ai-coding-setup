# Test Prompts for Local AI Coding

These prompts were used to test Qwen3.5-35B-A3B and Gemma 4 31B running locally via llama-server + OpenCode. They're designed to test different capabilities and can be used to benchmark any local model.

## Test 1: Single-File Game (Asteroids)

**Complexity**: Medium | **Tools Used**: None
**Qwen3.5 Result**: 519 lines, working with minor fixes (screen wrapping, bullet cleanup)
**Gemma 4 Result**: Working perfectly on first try, zero bugs, clean OOP structure

```
You are an expert Python game developer. Write a complete, playable "Asteroids" arcade clone in a single Python script using the `pygame` library.

### ARCHITECTURE & CONSTRAINTS
- **Zero Assets:** Render everything using `pygame.draw.polygon` (for the ship and asteroids) and `pygame.draw.circle` or lines for bullets.
- **Paradigm:** Use clean Object-Oriented Programming (classes for `Ship`, `Asteroid`, `Bullet`).
- **Typing:** Use strict Python type hints (`float`, `Tuple`, `List`).
- **Completeness:** Provide the ENTIRE script in a single python code block. No placeholders.

### CORE MECHANICS
1. **The Ship:** A triangle that rotates left/right with the arrow keys. Up arrow applies forward thrust in the direction it's facing (using vector math/trigonometry). Include momentum and slight friction/drag.
2. **Screen Wrapping:** If the ship, bullets, or asteroids go off one side of the screen, they must seamlessly appear on the opposite side.
3. **Shooting:** Spacebar fires bullets from the front of the ship.
4. **Asteroids:** Floating polygons of varying sizes. When shot, a large asteroid must split into two medium ones, and a medium into two small ones.
5. **Game Loop:** Score tracking, level progression (more asteroids spawn when the screen is cleared), and a Game Over state upon ship collision.
```

---

## Test 2: Dashboard with API Integration (Context7 MCP)

**Complexity**: Medium | **Tools Used**: Context7 | **Result**: 629 lines, working dashboard

```
Build a real-time cryptocurrency price dashboard as a single HTML file with embedded CSS and JavaScript.

## Step 1: Research
Use context7 to look up the CoinGecko API documentation. Find the correct endpoints for:
- Getting current prices for multiple coins (BTC, ETH, SOL, XRP) in USD
- Getting 7-day price history/sparkline data for each coin
- Understanding rate limits and required headers

## Step 2: Build the Dashboard
Create `dashboard.html` with these features:

### Layout
- Full-screen dark theme (#0a0a1a background)
- Header: "Crypto Dashboard" with current time and a 30-second countdown timer
- 4 glassmorphism cards in a responsive CSS Grid (2x2 on desktop, 1 column on mobile)
- Each card shows:
  - Coin icon (use unicode symbols)
  - Coin name and ticker
  - Current price in USD (formatted with commas and 2 decimals)
  - 24h % change with green (#00ff88) for positive, red (#ff4444) for negative
  - An inline SVG sparkline chart showing 7-day price trend
- Footer: "Last updated: [timestamp]" and "Data from CoinGecko"

### JavaScript
- Fetch prices from CoinGecko free API (no key needed)
- Auto-refresh every 30 seconds with visible countdown
- Error handling: show "API Error" state gracefully if fetch fails
- Loading skeleton state while data is being fetched

## Step 3: Verify
After creating the file, open it and check for any JavaScript errors or issues.
```

---

## Test 3: Complex Interactive App (Kanban Board + Chrome DevTools)

**Complexity**: Hard | **Tools Used**: Context7, Chrome DevTools | **Result**: 1,717 lines, working after bug fixes

```
Build an interactive Kanban board as a single HTML file. This must be a polished, production-quality SPA.

## Step 1: Research (use context7)
Use context7 to look up the HTML5 Drag and Drop API documentation. Find:
- How dragstart, dragover, dragenter, dragleave, drop events work
- Best practices for accessible drag and drop
- How to use dataTransfer correctly

## Step 2: Build the Kanban Board
Create `kanban.html` with these features:

### Core Functionality
- 4 columns: "Backlog", "In Progress", "Review", "Done"
- Cards with: title, description, priority tag (Low/Medium/High/Critical), assignee avatar (colored initials circle), created date
- Full drag-and-drop between columns with visual drop indicators
- Add new card via a modal form
- Delete cards with confirmation
- Edit cards inline
- Card count badge on each column header
- LocalStorage persistence

### Advanced Features
- Filter cards by priority using toggle buttons
- Search bar that filters cards in real-time
- Undo last action with Ctrl+Z
- Column WIP limits: "In Progress" max 3, "Review" max 2
- Smooth CSS animations
- Keyboard accessible

### Visual Design
- Dark theme with differentiated column backgrounds
- Priority-colored left borders on cards
- Glassmorphism effects
- Google Fonts: Inter

### Seed Data
Pre-populate with 8 sample cards across columns.

## Step 3: Browser Verification (use chrome-devtools)
After creating the file:
1. Open kanban.html in the browser using chrome-devtools
2. Take a screenshot
3. Run JavaScript to verify localStorage persistence
4. Check console for errors
5. Verify drag and drop by checking draggable attribute count
```

### Bugs Found & Fixed:
1. `e.preventDefault()` in `handleDragStart` — blocks drag entirely (should only be on `dragover`/`drop`)
2. `loadFromStorage()` loaded plain JSON objects instead of Card class instances — `toElement()` failed silently
3. Button detection used `classList[0]` which breaks when clicking emoji inside button — fixed with `closest()`

---

## Test 4: Full-Stack Application (JWT Auth + Next.js)

**Complexity**: Very Hard | **Tools Used**: Context7 | **Result**: Complete full-stack app, all features working

```
Build a full-stack JWT-authenticated dashboard with Next.js. This runs locally, no cloud services needed. Use SQLite for the database and local JWT tokens for auth.

## Step 1: Research (use context7)
Use context7 to look up:
- Next.js App Router documentation (route handlers, middleware, server components)
- Next.js API routes for building REST endpoints
- jose library for JWT token creation and verification in Edge runtime
- better-sqlite3 for SQLite database access in Node.js

## Step 2: Project Setup
Initialize the project:
npx create-next-app@latest auth-dashboard --typescript --tailwind --eslint --app --src-dir --no-import-alias
cd auth-dashboard
npm install jose better-sqlite3 bcryptjs
npm install -D @types/better-sqlite3 @types/bcryptjs

## Step 3: Database Layer
Create src/lib/db.ts:
- Initialize SQLite database at ./data/app.db
- Create users table: id, email, name, password_hash, role (admin/user), created_at
- Create activity_log table: id, user_id, action, details, created_at
- Seed with 2 users: admin@test.com / password123 (admin), user@test.com / password123 (user)

## Step 4: Auth Library
Create src/lib/auth.ts:
- Use jose library (Edge-compatible)
- Functions: signToken, verifyToken, hashPassword, comparePassword
- Token in httpOnly cookie named "auth-token", 24h expiry

## Step 5: API Routes
- POST /api/auth/login — validate credentials, set JWT cookie
- POST /api/auth/register — create user, set JWT cookie
- POST /api/auth/logout — clear cookie
- GET /api/auth/me — return current user
- GET /api/users — admin only, list all users
- GET /api/activity — activity log

## Step 6: Middleware
Protect /dashboard/*, allow /login, /register, /api/auth/*

## Step 7: Pages
- /login — login form, dark theme
- /register — registration form
- /dashboard — stats cards, recent activity
- /dashboard/users — admin only, user table
- /dashboard/activity — activity log with filters
- Sidebar layout with role-based navigation

## Step 8: Build and Verify
1. npm run build — check for errors
2. npm run dev — start server
3. Use chrome-devtools to verify login flow
4. Take screenshots

## Code Quality
- TypeScript strict mode
- Proper error handling (try/catch, correct HTTP status codes)
- Next.js App Router conventions
- Tailwind for styling
- Server components by default
```

---

## How to Use These Prompts

1. Start your llama-server (see scripts/)
2. Open OpenCode in your project directory
3. Paste the prompt
4. Watch it build

### Tips for Best Results with Local Models:
- **Always specify tool usage explicitly**: "use context7", "use chrome-devtools"
- **Break complex tasks into phases**: The model follows phased instructions well
- **Include seed data**: Pre-defined test data helps the model produce complete, testable output
- **Specify "no placeholders"**: Local models sometimes skip implementation details
- **Include verification steps**: Forces the model to self-check via tools

### Model Selection for Testing:
- **Qwen3.5-35B-A3B**: Faster iteration (188 t/s), good for rapid prototyping and multi-step agentic tasks. May need follow-up fixes.
- **Gemma 4 31B**: Slower (61 t/s) but higher first-shot quality. Better for single-prompt code generation where correctness matters most. Produced a bug-free Asteroids game on first try vs Qwen3.5 which needed minor fixes.
