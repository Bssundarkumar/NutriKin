# Exercise illustration generation

Generated with the built-in image_gen tool, October 1, 2026. These eight project assets cover the 129 catalog entries that previously had no illustration; the existing two sheets cover the other 24 exercises. All 153 built-in exercises are mapped by name in ExerciseIllustrations. User-created exercises retain a muscle-group icon until an illustration is supplied.

Each PNG is preserved as generated and rendered through a cached cell crop. Thumbnails fit within their cards to keep the athlete and equipment visible. Core, legs, and the original strength sheet use measured row boundaries because their generated grids have unequal row heights.

## Chest

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseChestVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 3 rows of equal square cells, overall aspect ratio 4:3. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Chest exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Incline bench press; Dumbbell press; Incline push-up; Decline push-up
Row 2, left to right: Knee push-up; Wide-grip bench press; Close-grip dumbbell press; Single-arm cable chest press
Row 3, left to right: Low-to-high cable fly; High-to-low cable fly; Dumbbell floor press; Squeeze press
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

## Back

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseBackVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 4 rows of equal square cells, overall aspect ratio 4:4. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Back exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Dumbbell row; T-bar row; Pull-up; Chin-up
Row 2, left to right: Back extension; Assisted pull-up; Neutral-grip pull-up; Wide-grip lat pulldown
Row 3, left to right: Underhand lat pulldown; Single-arm lat pulldown; Chest-supported row; Seal row
Row 4, left to right: Single-arm cable row; Inverted row; Straight-arm pulldown; EMPTY plain light gray cell
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

## Shoulders

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseShouldersVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 4 rows of equal square cells, overall aspect ratio 4:4. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Shoulders exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Dumbbell shoulder press; Arnold press; Front raise; Rear delt fly
Row 2, left to right: Upright row; Shrug; Standing dumbbell shoulder press; Landmine press
Row 3, left to right: Single-arm overhead press; Cable lateral raise; Lean-away lateral raise; Reverse pec deck
Row 4, left to right: Plate front raise; Pike push-up; EMPTY plain light gray cell; EMPTY plain light gray cell
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

## Arms

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseArmsVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 4 rows of equal square cells, overall aspect ratio 4:4. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Arms exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Preacher curl; Concentration curl; Skull crusher; Close-grip bench press
Row 2, left to right: Tricep dip; EZ-bar curl; Incline dumbbell curl; Cable curl
Row 3, left to right: Spider curl; Reverse curl; Zottman curl; Rope tricep pushdown
Row 4, left to right: Single-arm tricep pushdown; Dumbbell tricep kickback; Diamond push-up; EMPTY plain light gray cell
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

## Legs

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseLegsVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 6 rows of equal square cells, overall aspect ratio 4:6. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Legs exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Front squat; Goblet squat; Hack squat; Walking lunge
Row 2, left to right: Bulgarian split squat; Step-up; Leg extension; Leg curl
Row 3, left to right: Romanian deadlift; Calf raise; Wall sit; Reverse lunge
Row 4, left to right: Lateral lunge; Split squat; Smith machine squat; Single-leg press
Row 5, left to right: Seated leg curl; Lying leg curl; Single-leg Romanian deadlift; Seated calf raise
Row 6, left to right: Single-leg calf raise; Heel-elevated goblet squat; EMPTY plain light gray cell; EMPTY plain light gray cell
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

## Glutes

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseGlutesVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 4 rows of equal square cells, overall aspect ratio 4:4. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Glutes exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Glute bridge; Cable kickback; Sumo deadlift; Donkey kick
Row 2, left to right: Good morning; Single-leg hip thrust; Single-leg glute bridge; Banded glute bridge
Row 3, left to right: Frog pump; Fire hydrant; Banded lateral walk; Hip abduction machine
Row 4, left to right: Cable pull-through; Dumbbell hip thrust; EMPTY plain light gray cell; EMPTY plain light gray cell
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

## Core

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseCoreVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 6 rows of equal square cells, overall aspect ratio 4:6. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Core exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Plank; Side plank; Crunch; Sit-up
Row 2, left to right: Leg raise; Russian twist; Cable crunch; Ab wheel
Row 3, left to right: Mountain climber; Dead bug; Bicycle crunch; Reverse crunch
Row 4, left to right: Hanging knee raise; Hanging leg raise; Pallof press; Bird dog
Row 5, left to right: Hollow hold; Heel tap; Cable woodchop; Weighted plank
Row 6, left to right: Side plank hip lift; EMPTY plain light gray cell; EMPTY plain light gray cell; EMPTY plain light gray cell
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

## Full body

Saved asset: `FamilyFoodScanner/Assets.xcassets/ExerciseFullbodyVariations.imageset/atlas.png`

Final prompt:

```text
Use case: stylized-concept. Asset type: ONE tightly aligned exercise thumbnail sprite atlas for an iPhone fitness catalog. Create exactly 4 columns and 4 rows of equal square cells, overall aspect ratio 4:4. Every cell fills its exact grid position. No gutters, borders, headings, text, numbers, watermarks, or labels. Each cell has identical very light neutral gray studio background. Realistic polished 3D fitness illustration of a fit adult male with natural skin, black gym shorts and shoes, consistent style and soft lighting, like exercise app instructional thumbnails. Entire athlete and entire necessary equipment fit inside each cell with generous 8% padding. Clear recognizable exercise-specific posture, accurate equipment, no cropping, no overlapping cells. Distinguish each variation visibly (bench angle, grip, cable height, single leg or arm). This is a sprite atlas for Full body exercise thumbnails, NOT an infographic or UI screenshot.
EXACT cell assignment in row-major order:
Row 1, left to right: Burpee; Kettlebell swing; Clean and press; Thruster
Row 2, left to right: Farmer's carry; Turkish get-up; Dumbbell thruster; Kettlebell clean and press
Row 3, left to right: Single-arm kettlebell swing; Suitcase carry; Overhead carry; Bear crawl
Row 4, left to right: Battle ropes; Medicine ball slam; Sled push; Sled pull
Keep empty cells plain light gray. Do not repeat exercises or rearrange them.
```

