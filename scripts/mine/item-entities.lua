local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local vec = require("scripts/vector") --[[@as BlueprintShotgun.vector]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.item-entities
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    local entities = utils.find_entities_in_radius(params.surface, {
        position = params.target_pos,
        radius = 2,
        type = "item-entity"
    })
    table.sort(entities, utils.distance_sort(params.target_pos))

    if #entities == 0 then return end

    local i = 4 + params.bonus * 2
    for _, entity in pairs(entities) do
        game.play_sound{path = "utility/picked_up_item", position = entity.position}

        local position = entity.position
        local stack = entity.stack
        local sprite, shadow = render.draw_new_item(entity.surface, stack.name, entity.position, 0, 0)
        sprite.move_to_back()
        local slot = game.create_inventory(1)
        storage.vacuum_items[sprite] = {
            slot = slot,
            surface = params.surface,
            character = params.character,
            time = 0,
            position = position,
            velocity = vec.random(1/60),
            height = 0,
            orientation_deviation = utils.orientation_deviaiton(),
            shadow = shadow,
            deconstruct = entity.to_be_deconstructed() and params.character.force or nil,
        }
        slot[1].transfer_stack(stack) -- destroys the item

        params.ammo_item.drain_ammo(1/8)
        if not params.ammo_item.valid_for_read then break end

        i = i - 1
        if i == 0 then break end
    end

    return true
end

return lib
