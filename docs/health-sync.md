# Apple Health sync

Link the signed-in person's member profile to this iPhone through **Activity → Apple Health**, or **Family → My Apple Health**. Read and write permissions are chosen individually in Apple's permission sheet. Health data from this phone is never assigned to a different family member when switching Today tabs.

After linking, NutriKin refreshes on launch, foreground entry, day changes and Health observer updates. iOS controls background delivery timing; immediate live sync is not guaranteed. Background observer delivery requires the HealthKit background-delivery entitlement, included in `NutriKin/project.yml`.

- Reads steps, active calories, exercise minutes, workouts, nutrition, water, latest weight/height, glucose, blood pressure and sleep. Nutrition totals from other Health sources are added to the day's totals; this app's own exported nutrition is excluded to avoid double counting. Latest weight/height update the explicitly linked member's profile without re-exporting the imported measurement. Pending measurement writes prevent stale Health data from overriding a local change. Activity uses the larger of Health active energy and logged workout energy.
- External workouts automatically enter the linked member's family log. Imported workouts and NutriKin's own Health exports are excluded from re-export/import loops. Existing external IDs and matching manually entered workouts are deduplicated.
- Successful food and workout additions/edits/deletions update Health. Water uses 250 mL per glass; height/weight changes and growth readings export corresponding quantity samples. Strength sets are preserved as NutriKin workout metadata; Health's native workout UI does not display individual sets.
- Changes queue in a protected account/member-specific local outbox and retry on foreground or Health refresh. A stable sync identifier and version replace edited samples. Deletes target only NutriKin-created records with the matching entry/member metadata, leaving other apps' records alone.
- Sleep samples from overlapping sources are merged before summing. Sleep represents the previous 24 hours and is shown only on today's linked member, rather than incorrectly reusing it on historical days or relatives.
- Hunger, mood, medication dose logs, grocery lists and social groups do not have matching writable HealthKit samples; these remain in NutriKin.

Validation: simulator builds and unit tests cover nutrition units and totals, stable water keys, overlapping sleep, duplicate avoidance, protected outbox edit/delete coalescing and refusal to export another member's data. Read/write authorization, actual sample replacement/deletion, locked-phone background delivery and Watch/other-app updates require a signed build on a real iPhone and have not been tested in this session.

Apple references: [sync identifiers](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier), [observer queries](https://developer.apple.com/documentation/HealthKit/HKObserverQuery), [background delivery](https://developer.apple.com/documentation/HealthKit/HKHealthStore/enableBackgroundDelivery%28for%3Afrequency%3AwithCompletion%3A%29).

### Additional Activity readings

Activity now requests read access for heart rate, resting heart rate, walking/running distance, and flights climbed. Heart rate values use the average of available samples for the selected day; this is not a continuous or workout-only average. Distance uses the walking/running cumulative total in kilometres. Missing or denied readings stay unavailable (—). These readings are displayed only for the linked phone owner and are never written back as app measurements. Existing users can request the new types from Family → My Apple Health → Update Health permissions. Verify new permissions, date changes, missing samples and family-member isolation on a physical device before release.
