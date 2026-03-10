CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.ItemDefs = CaffeineMakesSense.ItemDefs or {}

local ItemDefs = CaffeineMakesSense.ItemDefs

-- Items whose vanilla fatigueChange we zero at boot and replace with our model.
-- Keys: item fullType. Values: { dose = caffeine dose strength, category = label, profile = key }.
ItemDefs.CAFFEINE_ITEMS = {
    ["Base.Coffee2"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.Teabag2"] = { dose = "DoseTea", category = "tea", profile = "tea" },
    ["Base.ChocolateCoveredCoffeeBeans"] = { dose = "DoseCoffeeBeans", category = "coffee_beans", profile = "coffee" },
    ["Base.HotDrink"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkClay"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkRed"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkSpiffo"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkWhite"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkMetal"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkCopper"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkGold"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkSilver"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkTumbler"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Base.HotDrinkTea"] = { dose = "DoseTea", category = "tea", profile = "tea" },
    ["Base.HotDrinkTeaCeramic"] = { dose = "DoseTea", category = "tea", profile = "tea" },
}

-- Fluids remain listed for reference. The brewed drink items above are the
-- active OnEat integration path in B42.
ItemDefs.CAFFEINE_FLUIDS = {
    ["Coffee"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee" },
    ["Tea"] = { dose = "DoseTea", category = "tea", profile = "tea" },
    ["GreenTea"] = { dose = "DoseTea", category = "tea", profile = "tea" },
}

-- Vitamin pills also have fatigueChange (caffeine pills in vanilla).
ItemDefs.CAFFEINE_PILLS = {
    ["PillsVitamins"] = { dose = "DoseVitamins", category = "vitamins", profile = "pill" },
}

return ItemDefs
