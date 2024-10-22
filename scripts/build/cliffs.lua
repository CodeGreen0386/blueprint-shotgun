local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local vec = require("scripts/vector") --[[@as BlueprintShotgun.vector]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.cliffs
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local cliffs = utils.find_entities_in_radius(params.surface, {
        type = "cliff",
        position = params.target_pos,
        radius = params.radius,
        to_be_deconstructed = true,
    })
    table.sort(cliffs, utils.distance_sort(params.target_pos))
    utils.arc_cull(cliffs, params.character.position, params.target_pos)

    for _, cliff in pairs(cliffs) do
        local explosive_name = cliff.prototype.cliff_explosive_prototype --[[@as string]]
        if params.inventory.get_item_count(explosive_name) == 0 then goto continue end

        if storage.to_explode[script.register_on_object_destroyed(cliff)] then goto continue end

        local capsule_action = game.item_prototypes[explosive_name].capsule_action --[[@as CapsuleAction]]
        local cliff_position = utils.get_bounding_box_center(cliff)
        local candidates = utils.find_entities_in_radius(params.surface, {
            type = "cliff",
            position = cliff_position,
            radius = capsule_action.radius * 1.5,
            to_be_deconstructed = true,
        })

        local center = #candidates > 0 and vec.zero() or cliff_position
        for _, candidate in pairs(candidates) do
            local candidate_position = utils.get_bounding_box_center(candidate)
            center = vec.add(center, candidate_position)
        end
        center = vec.div(center, math.max(#candidates, 1))

        local to_explode = {}
        local exploding_cliffs = utils.find_entities_in_radius(params.surface, {
            type = "cliff",
            position = center,
            radius = capsule_action.radius + 1
        })
        for _, exploding_cliff in pairs(exploding_cliffs) do
            local reg_id = script.register_on_object_destroyed(exploding_cliff)
            storage.to_explode[reg_id] = true
            to_explode[reg_id] = true
        end

        params.inventory.remove{name = explosive_name, count = 1}

        local id, shadow = render.draw_new_item(params.surface, explosive_name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, center)
        storage.flying_items[id] = {
            action = "cliff",
            surface = params.surface,
            force = params.character.force,
            name = explosive_name,
            source_pos = params.source_pos,
            target_pos = center,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviaiton(),
            shadow = shadow,
            to_explode = to_explode
        } --[[@as FlyingCliffExplosiveItem]]

        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end
end

---@param item FlyingCliffExplosiveItem
function lib.action(item)
    item.surface.create_entity{
        name = item.name,
        position = item.target_pos,
        target = item.target_pos,
        speed = 1,
    }

    local tick = game.tick + 1
    local queue = storage.remove_explode_queue[tick] or {}
    storage.remove_explode_queue[tick] = queue
    for reg_id in pairs(item.to_explode) do
        queue[#queue+1] = reg_id
    end
end

function lib.on_tick(event)
    local queue = storage.remove_explode_queue[event.tick]
    if not queue then return end
    for _, reg_id in pairs(queue) do
        storage.to_explode[reg_id] = nil
    end
    storage.remove_explode_queue[event.tick] = nil
end

return lib

---@class FlyingCliffExplosiveItem:FlyingItemBase
---@field action "cliff"
---@field to_explode table<uint, true>