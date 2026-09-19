---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"

local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local ghosts = utils.find_entities_in_radius(params.surface, {
        type = "entity-ghost",
        position = params.target_pos,
        radius = params.radius,
        force = params.character.force,
    }, true)
    table.sort(ghosts, utils.distance_sort(params.target_pos))
    utils.arc_cull(ghosts, params.character.position, params.target_pos)

    local used = false

    for _, ghost in pairs(ghosts) do
        if storage.to_build[ghost.unit_number] then goto continue end

        if not params.surface.can_place_entity{
            name = ghost.ghost_name,
            position = ghost.position,
            direction = ghost.direction,
            force = ghost.force
        } then
            goto continue
        end

        ---@cast ghost.ghost_prototype.items_to_place_this -?
        local item, stack = utils.find_place_result_stack(params.inventory, ghost.ghost_prototype.items_to_place_this, ghost.quality)
        if not item then goto continue end
        ---@cast stack -?

        local slot = game.create_inventory(1)
        slot[1].transfer_stack(stack, item.count)

        local sprite, shadow = render.draw_new_item(params.surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, ghost.position)
        storage.flying_items[sprite.id] = {
            action = "build",
            slot = slot,
            surface = params.surface,
            force = params.character.force,
            source_pos = params.source_pos,
            target_pos = ghost.position,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviation(),
            sprite = sprite,
            shadow = shadow,
            target_entity = ghost,
            unit_number = ghost.unit_number,
        } --[[@as FlyingBuildItem]]

        ---@cast ghost.unit_number -?
        storage.to_build[ghost.unit_number] = true

        used = true
        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end

    return used
end

---@param item FlyingBuildItem
local function try_revive(item)
    local target_entity = item.target_entity --[[@as LuaEntity]]
    if not target_entity.valid then return end

    local item_name = item.slot[1].name
    for _, place in pairs(target_entity.ghost_prototype.items_to_place_this --[[@as ItemToPlace[] ]]) do
        if place.name == item_name then
            goto forelse
        end
    end
    do return end
    ::forelse::

    local tags = target_entity.tags
    local success, entity = target_entity.revive() ---@cast entity LuaEntity
    if success == nil then return end

    entity.health = item.slot[1].health * entity.prototype.get_max_health(entity.quality)

    local stats = entity.force.get_entity_build_count_statistics(entity.surface)
    stats.on_flow(entity, 1)

    script.raise_script_revive{entity = entity, tags = tags}

    return true
end

---@param item FlyingBuildItem
function lib.action(item)
    if not try_revive(item) then
        utils.spill_item(item)
    end
    storage.to_build[item.unit_number] = nil
end

return lib

---@class FlyingBuildItem:FlyingItemBase
---@field action "build"
---@field target_entity LuaEntity
---@field unit_number uint