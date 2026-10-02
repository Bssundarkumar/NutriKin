# Buddy group logging

Navigation starts at Gym Buddies group tiles. Open a group to see its roster, select participants for the chosen calendar day, and add workouts for those people. Selection is stored on this phone by signed-in account, group and local calendar day. Each new day defaults to the current user. Changing selection affects future saves, not previously logged sessions.

The group form uses the existing strength editor. Strength, cardio, yoga, abs and custom shortcuts use the chosen participants and date. Shared sets/reps/weights, duration, effort and note are copied identically to each participant; calorie estimates use each person's stored weight privately on the server. The submitting phone exports only its linked owner's workout to Health. Other participants' Health exports are not performed by this phone.

## Backend requirement

Apply `backend/migration_022_buddy_group_logging.sql` in the Supabase SQL editor after migration 021. This migration has been prepared locally, not deployed or database-tested in this task.

The security-definer RPC checks authenticated adult membership, checks every selected recipient's current adult membership, locks membership during the transaction, validates workout/set bounds and inserts all participant rows atomically. It does not change general workout update/delete permissions. A server batch UUID and exact request comparison protect retries from duplicate logging. The client freezes submitted details after a failed/uncertain save so Retry sends the original request.

Verify before release: successful multi-participant save; recipients from different households; nonmember rejection; removed or unlinked participants; invalid sets; failure rollback; identical retry returns original records; changed retry is rejected; day/member selection isolation; only owner's Health outbox receives a write. Source syntax checks have passed; full build and physical-device/backend checks remain pending.
