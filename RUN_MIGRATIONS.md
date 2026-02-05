# Run Database Migrations

The Supabase project URL is now correctly configured as `https://sctfvvhiiplllwrhcnku.supabase.co`.

## Run Migrations in Supabase Dashboard

1. Go to your Supabase dashboard: https://supabase.com/dashboard/project/sctfvvhiiplllwrhcnku

2. Click **SQL Editor** in the left sidebar

3. Click **New query**

4. **First Migration - Base Schema**:
   - Copy the entire contents of `supabase/schema.sql`
   - Paste into the SQL editor
   - Click **Run** (or Cmd/Ctrl + Enter)
   - You should see "Success. No rows returned"

5. **Second Migration - User Authentication**:
   - Copy the entire contents of `supabase/migration_add_user_auth.sql`
   - Paste into the SQL editor
   - Click **Run**
   - You should see "Success. No rows returned"

## Verify Migrations

After running both migrations, verify the tables were created:

1. In the SQL editor, run:
   ```sql
   SELECT table_name FROM information_schema.tables
   WHERE table_schema = 'public'
   ORDER BY table_name;
   ```

2. You should see these tables:
   - `conversation_state`
   - `messages`
   - `model_presets`
   - `predictions`
   - `sessions`

## Create Test User

1. Go to **Authentication** → **Users** in the left sidebar
2. Click **Add user** → **Create new user**
3. Enter:
   - Email: `test@example.com` (or your email)
   - Password: Choose a password
   - Check "Auto Confirm User" if available
4. Click **Create user**

## Test Login

After migrations and user creation:

```bash
# Start the application
./start.sh

# Try logging in at http://localhost:5173
# Use the email and password you created
```

If login fails, check the browser console for errors.
