# Supabase Setup Issues and Resolution

## Current Blockers

### 1. Incorrect Project Reference
- **Current value in `.env`**: `ectfvvhiipllwrhcnku` (19 characters)
- **Required format**: Exactly 20 characters (e.g., `abcdefghijklmnopqrst`)
- **Result**: DNS lookup fails for `ectfvvhiipllwrhcnku.supabase.co`

### 2. API Keys Appear Truncated
The keys in `.env` are shorter than typical Supabase JWT tokens:
- Anon key: `sb_publishable_...` (example - get from dashboard)
- Service role key: `sb_secret_...` (example - get from dashboard)

Real Supabase keys are JWT tokens (150+ characters).

## How to Fix

### Step 1: Get Correct Credentials from Supabase Dashboard

1. Go to your Supabase project: https://supabase.com/dashboard/project/_
2. Click on **Settings** (gear icon in left sidebar)
3. Click on **API** in the settings menu
4. Copy the **exact** values for:
   - **Project URL** (under "Project URL" section)
   - **anon/public key** (under "Project API keys" → click eye icon to reveal full key)
   - **service_role key** (under "Project API keys" → click eye icon to reveal full key)

5. Also copy from **Settings → General**:
   - **Reference ID** (this is your 20-character project reference)

### Step 2: Update `.env` File

Replace the values in `/Users/csells/Code/csells/aicouncil/.env`:

```bash
SUPABASE_URL=https://[YOUR-20-CHAR-PROJECT-REF].supabase.co
SUPABASE_ANON_KEY=[FULL-JWT-TOKEN-150+-CHARS]
SUPABASE_SERVICE_ROLE_KEY=[FULL-JWT-TOKEN-150+-CHARS]
SUPABASE_JWT_SECRET=[YOUR-JWT-SECRET-FROM-SETTINGS]

VITE_SUPABASE_URL=https://[YOUR-20-CHAR-PROJECT-REF].supabase.co
VITE_SUPABASE_ANON_KEY=[FULL-JWT-TOKEN-150+-CHARS]
```

### Step 3: Run Database Migrations

Once the correct credentials are in place, run these commands:

```bash
# Link to your Supabase project
supabase link --project-ref [YOUR-20-CHAR-PROJECT-REF]

# Run the main schema
supabase db push --db-url "postgresql://postgres:[YOUR-DB-PASSWORD]@db.[YOUR-PROJECT-REF].supabase.co:5432/postgres"
```

Or manually in the Supabase SQL Editor:
1. Go to **SQL Editor** in your Supabase dashboard
2. Run `supabase/schema.sql` first
3. Run `supabase/migration_add_user_auth.sql` second

### Step 4: Enable Authentication

1. In Supabase dashboard, go to **Authentication** → **Providers**
2. Enable **Email** provider if not already enabled
3. Disable email confirmation for development:
   - Go to **Authentication** → **Settings**
   - Uncheck "Enable email confirmations"
   - Or manually confirm your test user via **Authentication** → **Users**

### Step 5: Create Test User

In Supabase dashboard:
1. Go to **Authentication** → **Users**
2. Click **Add user** → **Create new user**
3. Enter email and password
4. User will be created and can log in immediately

### Step 6: Test the Connection

```bash
# Start the backend (requires correct .env)
cd /Users/csells/Code/csells/aicouncil
./start.sh

# In another terminal, test the API
curl -X POST http://localhost:8001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"your-test@email.com","password":"your-password"}'
```

## Database Schema Overview

The migrations create these tables with Row Level Security (RLS):

1. **sessions** - Conversation sessions (with `user_id`)
2. **messages** - Messages within sessions
3. **model_presets** - Saved model configurations (with `user_id`)
4. **predictions** - Tracked predictions (with `user_id`)
5. **conversation_state** - Multi-round conversation state

RLS policies ensure users can only see their own data.

## Verification Checklist

- [ ] Project URL resolves (try `curl https://[project-ref].supabase.co`)
- [ ] Project reference is exactly 20 characters
- [ ] API keys are full JWT tokens (150+ characters)
- [ ] Schema migrations have been run
- [ ] At least one test user exists in Authentication → Users
- [ ] Backend starts without errors
- [ ] Login works from frontend (http://localhost:5173)

## Common Issues

**"Failed to fetch" error**: Usually means backend is not running or wrong URL
**DNS resolution failure**: Project reference is incorrect
**401 Unauthorized**: API keys are invalid or truncated
**403 Forbidden**: RLS policies blocking access (ensure migrations ran)
**No users exist**: Create user in Authentication → Users panel
