import Foundation

/// Debug builds only: launch with `-demoMode` to skip sign-in and use sample data,
/// so screens can be looked at without an account. Not compiled into release builds.
enum Demo {
    #if DEBUG
    static let isOn = CommandLine.arguments.contains("-demoMode")
    static var startTab: String { CommandLine.arguments.drop { $0 != "-demoTab" }.dropFirst().first ?? "today" }
    static var opensProduct: Bool { CommandLine.arguments.contains("-demoProduct") }
    static var opensAsk: Bool { CommandLine.arguments.contains("-demoAsk") }
    static var opensMeals: Bool { CommandLine.arguments.contains("-demoMeals") }

    /// Sample chat for screenshots only: empty unless launched with -demoAsk, so real chats never start with it.
    static var askMessages: [(String, String)] { opensAsk ? sampleChat : [] }

    private static let sampleChat: [(String, String)] = [
        ("user", "Is this OK for everyone?"),
        ("assistant", "**Not really.** Nutella is about 56% sugar, so it's a poor fit for **Amma** (diabetes, 25 g sugar goal): one tablespoon already uses roughly a third of her day.\n\nIt contains **hazelnuts and milk**. Arjun has a tree-nut allergy, so it's a firm no for him.\n\nPriya can have a thin spread now and then. Want a lower-sugar swap?"),
    ]

    static let mealIdeas = MealIdeas(slots: [
        MealSlot(name: "Breakfast", dishes: [MealDish(name: "Vegetable upma with curd", kcal: 320, ingredients: ["semolina", "mixed vegetables", "curd"], why: "Fibre-rich and slow to digest.")]),
        MealSlot(name: "Lunch", dishes: [MealDish(name: "Dal, brown rice and cucumber salad", kcal: 430, ingredients: ["lentils", "brown rice", "cucumber"], why: "Plant protein with steady carbs."),
                                          MealDish(name: "Buttermilk", kcal: 40, ingredients: ["buttermilk", "cumin"], why: "Light and hydrating.")]),
        MealSlot(name: "Dinner", dishes: [MealDish(name: "Grilled fish with sauteed greens", kcal: 380, ingredients: ["fish", "spinach", "olive oil"], why: "Lean protein, low in saturated fat.")]),
        MealSlot(name: "Snacks", dishes: [MealDish(name: "Roasted chana and an apple", kcal: 180, ingredients: ["chickpeas", "apple"], why: "Keeps you full between meals.")]),
    ], tips: ["Drink a glass of water before each meal.", "Swap sugary tea for unsweetened tea with cinnamon."], removedForAllergy: 1)
    static var opensLogFood: Bool { CommandLine.arguments.contains("-demoLogFood") }
    static var opensLogWorkout: Bool { CommandLine.arguments.contains("-demoLogWorkout") }
    static var opensLogProduct: Bool { CommandLine.arguments.contains("-demoLogProduct") }
    static var scrollsToMeds: Bool { CommandLine.arguments.contains("-demoScrollMeds") }
    static var opensMeds: Bool { CommandLine.arguments.contains("-demoMeds") }
    static var opensMedEdit: Bool { CommandLine.arguments.contains("-demoMedEdit") }
    static var opensPlan: Bool { CommandLine.arguments.contains("-demoPlan") }
    static var opensPlate: Bool { CommandLine.arguments.contains("-demoPlate") }
    static var plateResults: Bool { CommandLine.arguments.contains("-demoPlateResults") }

    static var foodEntries: [FoodEntry] {
        let now = Date(), cal = Calendar.current
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now }
        let a = members[0].id, k = members[1].id
        return [
            FoodEntry(memberId: a, eatenAt: at(8, 10), label: "Vegetable upma with curd", source: .ai, calories: 320, sugarG: 4, carbsG: 48, sodiumMg: 420, satFatG: 2, proteinG: 9, fiberG: 6, fatG: 9),
            FoodEntry(memberId: a, eatenAt: at(10, 45), label: "Apple and almonds", source: .manual, calories: 180, sugarG: 15, carbsG: 24, sodiumMg: 2, satFatG: 1, proteinG: 4, fiberG: 5, fatG: 8),
            FoodEntry(memberId: a, eatenAt: at(13, 15), label: "Dal, brown rice, cucumber salad", source: .plate, calories: 470, sugarG: 6, carbsG: 78, sodiumMg: 520, satFatG: 2, proteinG: 16, fiberG: 9, fatG: 8),
            FoodEntry(memberId: k, eatenAt: at(8, 30), label: "Oat porridge with banana", source: .manual, calories: 260, sugarG: 12, carbsG: 46, sodiumMg: 90, satFatG: 1, proteinG: 8),
        ]
    }

    static var workouts: [Workout] {
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 6, minute: 45, second: 0, of: Date()) ?? Date()
        return [Workout(memberId: members[0].id, doneAt: morning, kind: "walking", minutes: 40, intensity: .moderate, caloriesBurned: 165, note: "Morning walk")]
    }

    static let medications: [Medication] = {
        let a = members[0].id
        return [
            Medication(memberId: a, name: "Vitamin D3", dose: "1 tablet", times: ["08:00"]),
            Medication(memberId: a, name: "Blood pressure tablet", dose: "5 mg", times: ["08:00", "20:00"]),
            Medication(memberId: a, name: "Calcium", dose: "1 tablet", times: ["13:00"], daysOfWeek: [1, 3, 5]),
        ]
    }()

    static var doseRecords: [DoseRecord] {
        let at8 = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        return [DoseRecord(medicationId: medications[0].id, memberId: members[0].id, dueAt: at8, status: .taken),
                DoseRecord(medicationId: medications[1].id, memberId: members[0].id, dueAt: at8, status: .taken)]
    }

    static let groceries: [GroceryItem] = [
        GroceryItem(name: "Whole wheat atta", quantity: "5 kg"), GroceryItem(name: "Curd", quantity: "1 kg"),
        GroceryItem(name: "Spinach", quantity: "2 bunches"), GroceryItem(name: "Lentils (toor dal)", quantity: "1 kg"),
        GroceryItem(name: "Unsweetened almond milk"), GroceryItem(name: "Bananas", quantity: "6"),
    ]

    static let plateItems: [PlateItem] = [
        PlateItem(name: "Basmati rice", grams: 180,
                  per100g: .init(calories: 130, sugarG: 0.1, carbsG: 28, sodiumMg: 1, satFatG: 0.1, proteinG: 2.7, fiberG: 0.4, fatG: 0.3),
                  confidence: .high, allergens: []),
        PlateItem(name: "Chicken curry", grams: 150,
                  per100g: .init(calories: 165, sugarG: 3, carbsG: 6, sodiumMg: 420, satFatG: 3.2, proteinG: 14, fiberG: 1.2, fatG: 10),
                  confidence: .medium, allergens: [.milk]),
        PlateItem(name: "Peanut chutney", grams: 30,
                  per100g: .init(calories: 320, sugarG: 5, carbsG: 12, sodiumMg: 500, satFatG: 5, proteinG: 12, fiberG: 6, fatG: 26),
                  confidence: .low, allergens: [.peanuts]),
    ]

    static let members: [Member] = [
        Member(name: "Amma", conditions: [.diabetes], goals: Goals(dailySugarGrams: 25), age: 54, heightCm: 158, weightKg: 72, sex: .female),
        Member(name: "Arjun", conditions: [.allergy(.nuts)], isManagedByParent: true, age: 8, sex: .male),
        Member(name: "Priya", conditions: [], age: 29, sex: .female),
    ]

    static var product: Product? { opensProduct ? sampleProduct : nil }

    static let sampleProduct: Product = {
        var p = Product(
            barcode: "3017620422003", name: "Nutella", brand: "Ferrero", imageURL: nil,
            ingredientsText: "Sugar, palm oil, hazelnuts 13%, skimmed milk powder 8.7%, fat-reduced cocoa 7.4%, emulsifier: lecithins (soya), vanillin",
            allergenTags: ["en:milk", "en:nuts", "en:soybeans"],
            nutrition: Nutrition(calories: 539, sugarG: 56.3, carbsG: 57.5, sodiumMg: 40, satFatG: 10.6,
                                 transFatG: 0, proteinG: 6.3, basis: "per 100 g"))
        p.ingredientAmounts = [
            IngredientAmount(id: "en:sugar", text: "Sugar", percent: 56, isStated: false),
            IngredientAmount(id: "en:palm-oil", text: "Palm oil", percent: 21, isStated: false),
            IngredientAmount(id: "en:hazelnut", text: "Hazelnuts", percent: 13, isStated: true),
            IngredientAmount(id: "en:skimmed-milk-powder", text: "Skimmed milk powder", percent: 8.7, isStated: true),
            IngredientAmount(id: "en:cocoa", text: "Fat-reduced cocoa", percent: 7.4, isStated: true),
        ]
        p.nutriScore = "e"; p.novaGroup = 4
        p.per100g = p.nutrition
        return p
    }()

    static let records: [ScanRecord] = [
        ScanRecord(barcode: "3017620422003", productName: "Nutella", brand: "Ferrero",
                   results: [.init(memberName: "Amma", score: 28, verdict: 0, blockedByAllergy: false),
                             .init(memberName: "Arjun", score: 0, verdict: 0, blockedByAllergy: true),
                             .init(memberName: "Priya", score: 61, verdict: 1, blockedByAllergy: false)],
                   alerts: ["Added sugars", "Palm / coconut oil"]),
        ScanRecord(barcode: "5449000000996", productName: "Coca-Cola Zero Sugar", brand: "Coca-Cola",
                   results: [.init(memberName: "Amma", score: 88, verdict: 2, blockedByAllergy: false),
                             .init(memberName: "Arjun", score: 84, verdict: 2, blockedByAllergy: false),
                             .init(memberName: "Priya", score: 90, verdict: 2, blockedByAllergy: false)],
                   alerts: ["Artificial sweeteners"], scannedAt: Date().addingTimeInterval(-86_400)),
    ]
    #else
    static let isOn = false
    static let startTab = "today"
    static let opensProduct = false
    static let opensPlate = false
    static let opensPlan = false
    static let opensMeds = false
    static let scrollsToMeds = false
    static let opensMedEdit = false
    static let medications: [Medication] = []
    static var doseRecords: [DoseRecord] { [] }
    static let opensLogFood = false
    static let opensLogWorkout = false
    static let opensLogProduct = false
    static let opensAsk = false
    static let opensMeals = false
    static let askMessages: [(String, String)] = []
    static let mealIdeas = MealIdeas(slots: [], tips: [], removedForAllergy: 0)
    static let plateResults = false
    static let plateItems: [PlateItem] = []
    static let foodEntries: [FoodEntry] = []
    static let workouts: [Workout] = []
    static let groceries: [GroceryItem] = []
    static let members: [Member] = []
    static let product: Product? = nil
    static let records: [ScanRecord] = []
    #endif
}
