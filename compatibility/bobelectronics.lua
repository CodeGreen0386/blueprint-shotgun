if not mods["bobelectronics"] then return end

for _, ingredient in pairs(data.raw.recipe["blueprint-shotgun"].ingredients --[[@cast -?]]) do
    if ingredient.name == "electronic-circuit" then
        ingredient.name = "bob-basic-circuit-board"
        break
    end
end