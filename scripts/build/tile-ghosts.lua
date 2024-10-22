local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.tile-ghosts
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local ghosts = utils.find_entities_in_radius(params.surface, {
        type = "tile-ghost",
        position = params.target_pos,
        radius = params.radius,
        force = params.character.force,
    })
    table.sort(ghosts, utils.distance_sort(params.target_pos))
    utils.arc_cull(ghosts, params.character.position, params.target_pos)

    for _, ghost in pairs(ghosts) do
        if storage.to_build[ghost.unit_number] then goto continue end

        local place_items = ghost.ghost_prototype.items_to_place_this ---@cast place_items -nil
        local item
        for _, place_item in pairs(place_items) do
            if params.inventory.get_item_count(place_item.name) >= place_item.count then
                item = place_item
                break
            end
        end
        if not item then goto continue end

        local sprite, shadow = render.draw_new_item(params.surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, ghost.position)
        storage.flying_items[sprite] = {
            action = "tile",
            surface = params.surface,
            force = params.character.force,
            name = item.name,
            source_pos = params.source_pos,
            target_pos = ghost.position,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviaiton(),
            shadow = shadow,
            target_entity = ghost,
            unit_number = ghost.unit_number,
        } --[[@as FlyingTileItem]]

        params.inventory.remove(item)

        storage.to_build[ghost.unit_number] = true

        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end
end

---@param item FlyingTileItem
function lib.action(item)
    local target_entity = item.target_entity --[[@as LuaEntity]]
    if target_entity.valid then
        local surface = item.surface
        ---@diagnostic disable-next-line: missing-parameter, param-type-mismatch
        local tile = surface.get_tile(target_entity.position)
        utils.spill_products(surface, target_entity.position, tile.prototype, item.force)
        target_entity.revive{raise_revive = true}
    else
        utils.spill_item(item)
    end
    storage.to_build[item.unit_number] = nil
end

return lib

---@class FlyingTileItem:FlyingItemBase
---@field action "tile"
---@field target_entity LuaEntity
---@field unit_number uint
