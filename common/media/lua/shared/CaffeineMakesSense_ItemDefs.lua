CaffeineMakesSense = CaffeineMakesSense or {}
CaffeineMakesSense.ItemDefs = CaffeineMakesSense.ItemDefs or {}

local ItemDefs = CaffeineMakesSense.ItemDefs

-- Items whose vanilla fatigueChange we zero at boot and replace with our model.
-- Keys: item fullType. Values: { dose = caffeine dose strength, category = label, profile = key }.
ItemDefs.CAFFEINE_ITEMS = {
    ["Base.Coffee2"] = { dose = "DoseCoffeePackage", category = "coffee_package", profile = "coffee" },
    ["Base.Teabag2"] = { dose = "DoseTeabag", category = "tea_bag", profile = "tea" },
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

-- True fluid-container beverages still use vanilla DrinkFluid(...) instead of
-- the Food OnEat seam, so CMS keeps this map alive for those consume paths.
ItemDefs.CAFFEINE_FLUIDS = {
    ["Coffee"] = { dose = "DoseCoffee", category = "coffee", profile = "coffee", vanillaFatigueChange = -0.10 },
    ["Tea"] = { dose = "DoseTea", category = "tea", profile = "tea", vanillaFatigueChange = -0.05 },
    ["GreenTea"] = { dose = "DoseTea", category = "tea", profile = "tea", vanillaFatigueChange = -0.05 },
}

-- Vitamin pills also have fatigueChange (caffeine pills in vanilla).
ItemDefs.CAFFEINE_PILLS = {
    ["PillsVitamins"] = { dose = "DoseVitamins", category = "vitamins", profile = "pill" },
}

return ItemDefs
