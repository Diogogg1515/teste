import { createClient } from '@supabase/supabase-js';
const supabase = createClient('https://smuiikquxjqfnfoxbnyw.supabase.co', 'sb_publishable_v0sQHvlV7PJUH8wUZq8-uQ_uFAMAhRU');

async function check() {
  // Try to query information_schema
  const sql = "SELECT * FROM information_schema.tables WHERE table_schema = 'supabase_migrations'";
  const { data, error } = await supabase.rpc('query', { sql: sql });
  console.log('Tables:', data);
  console.log('Error:', error);
}
check();