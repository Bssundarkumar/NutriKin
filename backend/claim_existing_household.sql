-- OPTIONAL, one-off. Only needed if you want to keep the test family you
-- created before sign-in existed (it has no owner, so nobody can see it).
--
-- 1. Install the sign-in build and sign in once (that creates your user).
-- 2. Run migration_005_auth.sql.
-- 3. Put your email and the old household's id below, then run this.
--    (If you'd rather start fresh, skip this and just create a new family.)

insert into household_users (household_id, user_id, role)
select h.id, u.id, 'owner'
from households h
join auth.users u on u.email = 'YOU@EXAMPLE.COM'
where h.id = 'b7ab18c5-6192-4a8b-aaea-b7cf8f7444db'
on conflict do nothing;
