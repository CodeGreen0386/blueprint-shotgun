---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"
local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

local actions = {
    build   = require("scripts/build/entity-ghosts").action,
    upgrade = require("scripts/build/upgrades").action,
    cliff   = require("scripts/build/cliffs").action,
    request = require("scripts/build/proxies").action,
    tile    = require("scripts/build/tile-ghosts").action,
}

local lib = {}

---@param event EventData.on_tick
function lib.on_tick(event)
    for id, item in pairs(storage.flying_items) do
        local time_remaining = item.end_tick - event.tick

        if time_remaining <= 0 then
            ---@diagnostic disable-next-line: param-type-mismatch
            actions[item.action](item)

            item.slot.destroy()
            item.sprite.destroy()
            item.shadow.destroy()
            storage.flying_items[id] = nil
            if item.ultracube_token then
                remote.call("Ultracube", "release_ownership_token", item.ultracube_token)
                remote.call("Ultracube", "hint_entity", item.target_entity --[[@as LuaEntity]])
            end

            goto continue
        end

        local duration = item.end_tick - item.start_tick -- 0 somehow
        local t = (1 - time_remaining / duration) ^ 0.9

        -- starting height                   v
        local height = ((duration / 5) * t + 1) * (1 - t)
        local target = vec.sub(item.target_pos, item.source_pos)
        local lerp = vec.mul(target, t)
        local ground_pos = vec.add(item.source_pos, lerp)
        local air_pos = vec.add(ground_pos, {x = 0, y = -height})
        local shadow_pos = vec.add(ground_pos, {x = height, y = 0})

        if item.ultracube_token then
            remote.call("Ultracube", "update_ownership_token", item.ultracube_token, 60, {position = air_pos, velocity = vec.sub(air_pos, item.sprite.target.position)})
        end

        item.sprite.target = air_pos -- air_pos nan somehow
        item.sprite.orientation = item.sprite.orientation + item.orientation_deviation

        local scale = 1 / (height / 3 + 1)
        item.shadow.target = shadow_pos
        item.shadow.x_scale = scale
        item.shadow.y_scale = scale

        ::continue::
    end

    for id, item in pairs(storage.vacuum_items) do
        item.time = item.time + 1

        if not (item.falling or item.character.valid) then
            item.falling = item.time
        end

        if item.falling then
            item.height = item.height - ((item.time - item.falling) / 60)^2
            item.velocity = vec.mul(item.velocity, 0.975) -- air resistance
            item.position = vec.add(item.velocity, item.position)

            if item.height <= 0 then
                local ground_items = utils.exact_spill(item.surface, item.position, item.slot[1], item.deconstruct)
                game.play_sound{path = "utility/drop_item", position = item.position}
                item.slot.destroy()
                item.sprite.destroy()
                item.shadow.destroy()
                storage.vacuum_items[id] = nil
                if item.ultracube_token then
                    remote.call("Ultracube", "release_ownership_token", item.ultracube_token)
                    remote.call("Ultracube", "hint_entity", ground_items[1] --[[@as LuaEntity]])
                end
                goto continue
            end
        else
            local character_vector = vec.sub(item.character.position, item.position)
            if vec.dist2(item.position, item.character.position) <= vec.len(character_vector) then
                local stack = item.slot[1]
                local inserted_count = item.character.insert(stack)
                if stack.count > inserted_count then
                    stack.count = stack.count - inserted_count
                    item.falling = item.time
                    local player = item.character.player
                    if player then
                        local localised_name = {"?", prototypes.item[stack.name].localised_name, stack.name}
                        local message = {"inventory-restriction.player-inventory-full", localised_name, {"inventory-full-message.main"}}
                        player.print(message, {skip = defines.print_skip.if_visible})
                    end
                else
                    item.slot.destroy()
                    item.sprite.destroy()
                    item.shadow.destroy()
                    storage.vacuum_items[id] = nil
                    if item.ultracube_token then
                        remote.call("Ultracube", "release_ownership_token", item.ultracube_token)
                        remote.call("Ultracube", "hint_entity", item.character)
                    end
                    goto continue
                end
            end

            local new_velocity = vec.mul(vec.norm(character_vector), item.time / 120)
            if item.time < 60 then
                local weight = math.max(0, item.time / 60)
                local initial = vec.mul(item.velocity, 1 - weight)
                local target = vec.mul(new_velocity, weight)
                new_velocity = vec.add(initial, target)
            end

            item.height = item.height + 1/30 * (1 - item.height)
            item.velocity = new_velocity
            item.position = vec.add(new_velocity, item.position)

            if item.ultracube_token then
                remote.call("Ultracube", "update_ownership_token", item.ultracube_token, 60, {position = item.position, velocity = new_velocity})
            end
        end

        item.sprite.target = vec.add(item.position, {x = 0, y = -item.height})
        item.shadow.target = vec.add(item.position, {x = item.height, y = 0})

        local scale = 1 / (item.height / 3 + 1)
        item.shadow.x_scale = scale
        item.shadow.y_scale = scale

        item.sprite.orientation = item.sprite.orientation + item.orientation_deviation * math.min(1, item.time / 30)

        ::continue::
    end
end

return lib

---@alias FlyingItem FlyingCliffExplosiveItem|FlyingBuildItem|FlyingUpgradeItem|FlyingRequestItem|FlyingTileItem

---@class FlyingItemBase
---@field slot LuaInventory
---@field surface LuaSurface
---@field force ForceID
---@field source_pos MapPosition
---@field target_pos MapPosition
---@field start_tick uint
---@field end_tick uint
---@field orientation_deviation number
---@field sprite LuaRenderObject
---@field shadow LuaRenderObject
---@field ultracube_token uint?

---@class VacuumItem
---@field slot LuaInventory
---@field surface LuaSurface
---@field character LuaEntity
---@field time uint
---@field falling uint?
---@field position MapPosition
---@field velocity Vector
---@field height number
---@field orientation_deviation number
---@field sprite LuaRenderObject
---@field shadow LuaRenderObject
---@field deconstruct ForceID?
---@field ultracube_token uint?