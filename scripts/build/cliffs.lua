---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"
local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

---@type table<string, LuaItemPrototype>
local cliff_explosive_items = {}
for _, cliff in pairs(prototypes.get_entity_filtered{{filter = "type", type = "cliff"}}) do
    local name = cliff.cliff_explosive_prototype
    if name then
        cliff_explosive_items[name] = prototypes.item[name]
    end
end

---@type table<string, string>
local projectiles = {}
for name, item in pairs(cliff_explosive_items) do
    for _, action in pairs(item.capsule_action.attack_parameters.ammo_type.action --[[@as TriggerItem[] ]]) do
        if action.action_delivery then
            for _, delivery in pairs(action.action_delivery) do
                if delivery.type == "projectile" then
                    projectiles[name] = delivery.projectile -- assumes only projectile is cliff explosive
                elseif delivery.type == "stream" then
                    projectiles[name] = delivery.stream
                end
            end
        end
    end
end

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

    local used = false

    for _, cliff in pairs(cliffs) do
        local explosive_name = cliff.prototype.cliff_explosive_prototype --[[@as string]]
        local count, quality = utils.get_item_count_aq(params.inventory, explosive_name)
        if count == 0 then goto continue end

        if storage.to_explode[script.register_on_object_destroyed(cliff)] then goto continue end

        local capsule_action = prototypes.item[explosive_name].capsule_action --[[@as CapsuleAction]]
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

        local slot = game.create_inventory(1)
        local stack = params.inventory.find_item_stack{name = explosive_name, quality = quality} ---@cast stack LuaItemStack
        slot[1].transfer_stack(stack, 1)

        local sprite, shadow = render.draw_new_item(params.surface, explosive_name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, center)
        storage.flying_items[sprite.id] = {
            action = "cliff",
            slot = slot,
            surface = params.surface,
            force = params.character.force,
            source_pos = params.source_pos,
            target_pos = center,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviation(),
            sprite = sprite,
            shadow = shadow,
            to_explode = to_explode
        } --[[@as FlyingCliffExplosiveItem]]

        used = true
        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end

    return used
end

---@param item FlyingCliffExplosiveItem
function lib.action(item)
    item.surface.create_entity{
        name = projectiles[item.slot[1].name],
        position = item.target_pos,
        source = item.target_pos,
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