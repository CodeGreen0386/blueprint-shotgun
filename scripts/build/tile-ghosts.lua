---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"
local cmu = require("collision-mask-util") ---@diagnostic disable-line: unresolved-require

local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local surface = params.surface
    local ghosts = utils.find_entities_in_radius(surface, {
        type = "tile-ghost",
        position = params.target_pos,
        radius = params.radius,
        force = params.character.force,
    })
    table.sort(ghosts, utils.distance_sort(params.target_pos))
    utils.arc_cull(ghosts, params.character.position, params.target_pos)

    local used = false

    for _, ghost in pairs(ghosts) do
        if storage.to_build[ghost.unit_number] then goto continue end

        local item = ghost.ghost_prototype.items_to_place_this[1]
        local prototype = prototypes.item[item.name]
        local tile_result = prototype.place_as_tile_result --[[@as PlaceAsTileResult]]
        local mask = tile_result.condition

        local tile = surface.get_tile(ghost.position) ---@diagnostic disable-line
        if cmu.masks_collide(mask, tile.prototype.collision_mask) ~= tile_result.invert then goto continue end

        local count, quality = utils.get_item_count_aq(params.inventory, item.name)
        if count < item.count then
            goto continue
        end

        local slot = game.create_inventory(1)
        local stack = params.inventory.find_item_stack{name = item.name, quality = quality} ---@cast stack LuaItemStack
        slot[1].transfer_stack(stack, item.count) -- possible dupe bug with manual inventory sorting when count > 1 but I do not care

        local sprite, shadow = render.draw_new_item(surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, ghost.position)
        storage.flying_items[sprite.id] = {
            action = "tile",
            slot = slot,
            surface = surface,
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
        } --[[@as FlyingTileItem]]

        ---@cast ghost.unit_number -?
        storage.to_build[ghost.unit_number] = true

        used = true
        params.ammo_item.drain_ammo(0.25)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end

    return used
end

---@param item FlyingTileItem
function lib.action(item)
    local target_entity = item.target_entity --[[@as LuaEntity]]
    if target_entity.valid then
        local surface = item.surface
        local position = target_entity.position

        ---@diagnostic disable-next-line: missing-parameter, param-type-mismatch
        local old = surface.get_tile(position)
        if old.prototype.is_foundation == target_entity.ghost_prototype.is_foundation then
            local character = utils.temp_character(surface, target_entity.force)
            character.mine_tile(old)
            surface.spill_inventory{
                inventory = character.get_main_inventory() --[[@as LuaInventory]],
                position = position,
                force = target_entity.force,
                allow_belts = false,
            }
            character.destroy()
        end

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