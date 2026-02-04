# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LLM Council is a multi-mode deliberation system where multiple LLMs collaborate to answer questions. The flagship mode is a 3-stage process: individual responses, anonymized peer review, and chairman synthesis. Additional modes include debate, adversarial challenge, socratic questioning, and scenario planning.

## Development Commands

### Running the Application

**Quick start (both backend and frontend):**
```bash
./start.sh
```

**Manual start:**
```bash
# Backend (from project root)
uv run python -m backend.main
# OR
python -m backend.main

# Frontend (from project root)
cd frontend && npm run dev
```

Backend runs on port 8001, frontend on port 5173.

### Frontend Commands
```bash
cd frontend
npm install          # Install dependencies
npm run dev          # Start dev server (port 5173)
npm run build        # Production build
npm run preview      # Preview production build
npm run lint         # Run ESLint
```

### Backend Commands
```bash
# From project root
python -m backend.main                # Run backend server
uv run python -m backend.main         # Run with uv (recommended)

# Install dependencies
pip install -r requirements.txt
# OR with uv (if available)
uv sync
```

**CRITICAL**: Always run backend as `python -m backend.main` from project root, NOT from inside the backend directory. This is required for Python's relative import system to work correctly.

## Architecture

### System Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     Frontend    │────▶│  FastAPI/Vercel │────▶│   OpenRouter    │
│   (React/Vite)  │     │    (Backend)    │     │   (LLM APIs)    │
└────────┬────────┘     └────────┬────────┘     └─────────────────┘
         │                       │
         │ Auth (JWT)            │ Service Role
         ▼                       ▼
┌─────────────────────────────────────────────┐
│              Supabase                        │
│  ┌─────────────┐  ┌─────────────────────┐   │
│  │    Auth     │  │   PostgreSQL + RLS   │   │
│  └─────────────┘  └─────────────────────┘   │
└─────────────────────────────────────────────┘
```

**Key Points:**
- Frontend: React with Vite, Supabase client for authentication
- Backend: FastAPI with async/await, OpenRouter for LLM access
- Database: Supabase PostgreSQL with Row Level Security (RLS)
- Authentication: Supabase Auth with JWT tokens, invite-only model
- Deployment: Vercel serverless (both frontend and backend)

### Council Modes

The system supports multiple deliberation modes (configured in [config.py:34](backend/config.py#L34)):

- **Synthesized** (default): 3-stage process with peer review and synthesis
- **Independent**: All models respond separately, no synthesis
- **Debate**: Multi-round discussion where models respond to each other
- **Adversarial**: Three models answer while a Devil's Advocate challenges
- **Socratic**: The council asks probing questions to clarify user thinking
- **Scenario Planning**: Models generate best/worst/likely scenarios

Council types (general, business strategy, code review, creative writing, etc.) and specialist roles (optimist, skeptic, pragmatist, innovator) can be configured via the UI.

### Backend Structure (`backend/`)

**`config.py`**
- Contains `DEFAULT_COUNCIL_MODELS` and `DEFAULT_CHAIRMAN_MODEL` (user can override via UI)
- Defines `COUNCIL_MODES` with metadata for each mode type
- Defines council types (general, business, code review, etc.) and specialist roles
- Uses environment variable `OPENROUTER_API_KEY` from `.env`
- Backend runs on **port 8001** (NOT 8000 - user had another app on 8000)

**`auth.py`**
- JWT token verification using Supabase JWT secret
- `verify_token()`: Validates tokens and extracts user_id
- `get_current_user()`: FastAPI dependency for route protection
- All authenticated routes receive `user_id` from JWT claims

**`supabase_db.py`**
- Primary database layer using Supabase client
- Replaces legacy JSON file storage
- Functions for conversations, messages, presets, predictions
- Row Level Security (RLS) ensures users only access their own data
- Uses service role key to bypass RLS on backend (security is enforced by auth layer)

**`models_api.py`**
- Exposes `/api/models` endpoint to fetch available OpenRouter models
- Caches model list to avoid repeated API calls
- Used by frontend for dynamic model selection

**`openrouter.py`**
- `query_model()`: Single async model query
- `query_models_parallel()`: Parallel queries using `asyncio.gather()`
- Returns dict with 'content' and optional 'reasoning_details'
- Graceful degradation: returns None on failure, continues with successful responses

**`council.py`** - The Core Logic
- `stage1_collect_responses()`: Parallel queries to all council models
- `stage2_collect_rankings()`:
  - Anonymizes responses as "Response A, B, C, etc."
  - Creates `label_to_model` mapping for de-anonymization
  - Prompts models to evaluate and rank (with strict format requirements)
  - Returns tuple: (rankings_list, label_to_model_dict)
  - Each ranking includes both raw text and `parsed_ranking` list
- `stage3_synthesize_final()`: Chairman synthesizes from all responses + rankings
- `parse_ranking_from_text()`: Extracts "FINAL RANKING:" section, handles both numbered lists and plain format
- `calculate_aggregate_rankings()`: Computes average rank position across all peer evaluations

**`main.py`**
- FastAPI app with async/await throughout
- CORS enabled for configured origins (localhost:5173 for dev)
- Authentication middleware on all routes except health checks
- POST `/api/conversations/{id}/message` - Main council endpoint, returns all 3 stages + metadata
- GET `/api/conversations` - List user's conversations
- POST `/api/conversations` - Create new conversation
- DELETE `/api/conversations/{id}` - Archive conversation
- Additional endpoints for presets, predictions, model configuration
- Metadata (label_to_model, aggregate_rankings) is ephemeral, not persisted to database

### Deployment Structure (`api/`)

**`api/index.py`**
- Vercel serverless function entry point
- Imports and exposes the FastAPI app from backend/main.py
- Enables deployment to Vercel's Python runtime
- Do not confuse this with the backend code; it's just a thin wrapper

### Frontend Structure (`frontend/src/`)

**`supabase.js`**
- Supabase client initialization for authentication
- Uses `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` environment variables
- Provides auth state management

**`api.js`**
- Centralized API client for backend communication
- Automatically includes JWT token in Authorization header
- Base URL configurable via `VITE_API_URL` (defaults to same-origin)
- All endpoints return promises with error handling

**`App.jsx`**
- Main orchestration: manages authentication state, conversations, and routing
- Handles message sending and metadata storage
- Manages council mode and configuration state
- Important: metadata (label_to_model, aggregate_rankings) is stored in UI state for display but not persisted to backend

**`components/Login.jsx`**
- Authentication UI for Supabase Auth
- Email/password login with "forgot password" flow
- Invite-only model: users must be created by admin in Supabase dashboard

**`components/Sidebar.jsx`**
- Conversation list with archive functionality
- User profile dropdown with logout
- Displays conversation titles and timestamps

**`components/ModeSelector.jsx`**
- Dropdown for selecting council mode (synthesized, independent, debate, etc.)
- Configuration panel for council type and specialist roles
- Model selection overrides (optional)

**`components/ChatInterface.jsx`**
- Multiline textarea (3 rows, resizable)
- Enter to send, Shift+Enter for new line
- User messages wrapped in markdown-content class for padding
- Support for mid-session message injection via "Add User Message" button

**`components/DebateControls.jsx`**
- UI for multi-round debate mode
- "Continue Debate" button to trigger additional rounds
- Round counter and state management
- Only visible in debate/adversarial/socratic/scenario modes

**`components/Stage1.jsx`**
- Tab view of individual model responses
- ReactMarkdown rendering with markdown-content wrapper
- For debate modes, shows all rounds in chronological tabs
- Includes reasoning traces when available (for reasoning models)

**`components/Stage2.jsx`**
- **Critical Feature**: Tab view showing RAW evaluation text from each model
- De-anonymization happens CLIENT-SIDE for display (models receive anonymous labels)
- Shows "Extracted Ranking" below each evaluation so users can validate parsing
- Aggregate rankings shown with average position and vote count
- Explanatory text clarifies that boldface model names are for readability only
- Only shown in synthesized mode (hidden in other modes)

**`components/Stage3.jsx`**
- Final synthesized answer from chairman
- Green-tinted background (#f0fff0) to highlight conclusion
- Only shown in modes with synthesis enabled (synthesized, debate with synthesis)

**`components/ConfirmDialog.jsx`**
- Reusable confirmation modal for destructive actions
- Used for archiving conversations, clearing settings, etc.

**Styling (`*.css`)**
- Light mode theme (not dark mode)
- Primary color: #4a90e2 (blue)
- Global markdown styling in `index.css` with `.markdown-content` class
- 12px padding on all markdown content to prevent cluttered appearance

## Environment Configuration

### Required Environment Variables

Create a `.env` file in the project root:

```bash
# OpenRouter API (required)
OPENROUTER_API_KEY=sk-or-v1-your-key-here

# Supabase Backend (required)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_JWT_SECRET=your-jwt-secret

# Frontend Supabase (required)
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key

# CORS (required for production)
CORS_ORIGINS=http://localhost:5173,https://your-app.vercel.app

# Frontend API URL (optional, defaults to same-origin)
VITE_API_URL=
```

See `.env.example` for reference. Never commit the `.env` file.

### Database Setup

Run the schema files in Supabase SQL Editor:
1. `supabase/schema.sql` - Creates base tables
2. `supabase/migration_add_user_auth.sql` - Adds auth and RLS policies

## Key Design Decisions

### Authentication Flow

- **Invite-only model**: Users must be created by admin in Supabase dashboard
- JWT tokens issued by Supabase Auth, verified in backend
- All API routes protected except health checks
- Row Level Security (RLS) ensures data isolation between users
- Frontend uses Supabase client for auth, backend uses JWT verification

### Database Migration (JSON → Supabase)

- Original implementation used JSON files in `data/conversations/`
- Migrated to Supabase PostgreSQL for multi-user support and scalability
- Legacy `storage.py` module still exists but is unused
- All conversation data now stored in Supabase with RLS policies
- Additional tables for presets (saved configurations) and predictions (scenario planning)

### Stage 2 Prompt Format
The Stage 2 prompt is very specific to ensure parseable output:
```
1. Evaluate each response individually first
2. Provide "FINAL RANKING:" header
3. Numbered list format: "1. Response C", "2. Response A", etc.
4. No additional text after ranking section
```

This strict format allows reliable parsing while still getting thoughtful evaluations.

### De-anonymization Strategy
- Models receive: "Response A", "Response B", etc.
- Backend creates mapping: `{"Response A": "openai/gpt-5.1", ...}`
- Frontend displays model names in **bold** for readability
- Users see explanation that original evaluation used anonymous labels
- This prevents bias while maintaining transparency

### Error Handling Philosophy
- Continue with successful responses if some models fail (graceful degradation)
- Never fail the entire request due to single model failure
- Log errors but don't expose to user unless all models fail

### UI/UX Transparency
- All raw outputs are inspectable via tabs
- Parsed rankings shown below raw text for validation
- Users can verify system's interpretation of model outputs
- This builds trust and allows debugging of edge cases

## Important Implementation Details

### Relative Imports
All backend modules use relative imports (e.g., `from .config import ...`) not absolute imports. This is critical for Python's module system to work correctly when running as `python -m backend.main`.

### Port Configuration
- Backend: 8001 (changed from 8000 to avoid conflict with other apps)
- Frontend: 5173 (Vite default)
- Update both `backend/main.py` and `frontend/src/api.js` if changing

### Markdown Rendering
All ReactMarkdown components must be wrapped in `<div className="markdown-content">` for proper spacing. This class is defined globally in `index.css`.

### Model Configuration
- Default models defined in `backend/config.py` as `DEFAULT_COUNCIL_MODELS` and `DEFAULT_CHAIRMAN_MODEL`
- Users can override models per-conversation via UI (stored in conversation metadata)
- Frontend fetches available models from `/api/models` endpoint
- Models use OpenRouter identifiers (e.g., `openai/gpt-5.2`, `anthropic/claude-opus-4.5`)

### Deployment

**Vercel Configuration:**
- Frontend and backend both deploy to Vercel as serverless functions
- `api/index.py` serves as the entry point for backend serverless function
- `vercel.json` configures routing: `/api/*` goes to Python runtime, everything else to frontend
- Environment variables must be set in Vercel dashboard (see [DEPLOYMENT.md](DEPLOYMENT.md))

**Streaming Limitation:**
- App supports real-time streaming where model responses appear as they complete
- Works perfectly in local development
- Vercel's Python runtime buffers responses, so production shows results all at once
- For true streaming in production, deploy backend to Railway, Render, or Fly.io and set `VITE_API_URL`

### Council Presets
- Users can save council configurations as presets (stored in Supabase)
- Presets include: mode, council type, specialist roles, model overrides
- Applied via dropdown in ModeSelector component
- Useful for recurring use cases (e.g., "Code Review Council", "Business Strategy Session")

## Common Gotchas

1. **Module Import Errors**: Always run backend as `python -m backend.main` from project root, not from backend directory. This is required for relative imports to work.

2. **CORS Issues**:
   - Frontend must match allowed origins in `CORS_ORIGINS` environment variable
   - No trailing slashes in origin URLs
   - Update `.env` for local dev and Vercel environment variables for production

3. **Authentication Errors**:
   - "Session expired": JWT token expired, refresh the page
   - "Invalid login credentials": User doesn't exist in Supabase or wrong password
   - Check `SUPABASE_JWT_SECRET` matches your Supabase project settings

4. **Database Connection Issues**:
   - Verify `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are correct
   - Ensure schema migrations have been run in Supabase SQL Editor
   - RLS policies must be in place or backend won't be able to query user data

5. **Ranking Parse Failures**:
   - If models don't follow "FINAL RANKING:" format, fallback regex extracts any "Response X" patterns in order
   - Check [council.py:parse_ranking_from_text](backend/council.py) for parsing logic

6. **Missing Metadata**:
   - `label_to_model` and `aggregate_rankings` are ephemeral (not persisted to database)
   - Only returned in API responses and stored in frontend state
   - Refreshing the page will lose this metadata

7. **Environment Variables Not Loading**:
   - Frontend: Must use `VITE_` prefix for environment variables to be accessible
   - Backend: No prefix needed, loaded via `python-dotenv`
   - Vercel: Set in dashboard, no `.env` file needed in deployment

## Data Flow Summary

### Authenticated Request Flow

```
User Login (Supabase Auth)
    ↓
Frontend receives JWT token
    ↓
JWT sent with each API request (Authorization header)
    ↓
Backend verifies JWT → extracts user_id
    ↓
Database queries filtered by user_id (RLS)
```

### Council Response Flow (Synthesized Mode)

```
User Query (with JWT token)
    ↓
Stage 1: Parallel queries to all council models → [individual responses]
    ↓
Stage 2: Anonymize responses (Response A, B, C...)
    ↓
        Parallel ranking queries → [evaluations + parsed rankings]
    ↓
        Calculate aggregate rankings → [sorted by avg position]
    ↓
Stage 3: Chairman synthesis with full context
    ↓
Return: {stage1, stage2, stage3, metadata}
    ↓
Save to Supabase (user_id, conversation_id, message)
    ↓
Frontend: Display with tabs + validation UI
```

The entire flow is async/parallel where possible to minimize latency. Each stage uses `asyncio.gather()` for concurrent LLM queries.

### Other Council Modes

- **Independent**: Stage 1 only, no synthesis
- **Debate**: Multi-round Stage 1 with context from previous rounds, optional synthesis at end
- **Adversarial**: Stage 1 with Devil's Advocate + 3 advocates, optional synthesis
- **Socratic**: Council asks user questions instead of answering (no synthesis)
- **Scenario Planning**: Models generate scenarios, saved to predictions table

## Development Workflow

### Adding a New Council Mode

1. Add mode definition to `COUNCIL_MODES` in [config.py](backend/config.py)
2. Implement mode logic in [council.py](backend/council.py) (new function or extend existing)
3. Add frontend UI handling in [App.jsx](frontend/src/App.jsx)
4. Update [ModeSelector.jsx](frontend/src/components/ModeSelector.jsx) if needed
5. Test with various model combinations

### Adding a New API Endpoint

1. Define route in [main.py](backend/main.py) with `@app.get/post/delete`
2. Add authentication decorator: `user_id: str = Depends(get_current_user)`
3. Implement database operations in [supabase_db.py](backend/supabase_db.py)
4. Add client function in [api.js](frontend/src/api.js)
5. Integrate into frontend components

### Modifying Stage 2 Parsing

The Stage 2 ranking parser is fragile by nature (parsing LLM outputs). If models fail to follow format:

1. Check prompt in [council.py:stage2_collect_rankings](backend/council.py)
2. Review fallback regex in [council.py:parse_ranking_from_text](backend/council.py)
3. Test with multiple models to ensure broad compatibility
4. Consider adding model-specific parsing if certain models consistently fail
