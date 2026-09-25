import Foundation

/// Project connection details for Supabase.
///
/// The anon/public key is safe to ship in the app — it identifies the
/// project, not a user, and every table it can touch is protected by the
/// Row Level Security policies in `backend/schema.sql`. Never put the
/// `service_role` key here.
enum SupabaseConfig {
    static let url = URL(string: "https://guihtuotohipipagkbri.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd1aWh0dW90b2hpcGlwYWdrYnJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxOTE3MzMsImV4cCI6MjEwNTc2NzczM30.0YhZF6e72akhWZ9NJBUvoZfwxEyYfPCnVLb5ye-OlLQ"
}
