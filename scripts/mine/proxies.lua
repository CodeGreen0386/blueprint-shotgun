---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"
local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

---@param params BlueprintShotgun.HandlerParams
return function(params)
    local entities = utils.find_entities_in_radius(params.surface, {
        type = "item-request-proxy",
        position = params.target_pos,
        radius = params.radius,
    })
    table.sort(entities, utils.distance_sort(params.target_pos))

    if #entities == 0 then return end

    local vacuum_limit = 4 + params.bonus * 2
    local prev_limit = vacuum_limit
    for _, proxy in pairs(entities) do
        local removal_plan = proxy.removal_plan
        if not removal_plan[1] then goto continue end

        local target = proxy.proxy_target
        if not target then goto continue end

        for i, plan in pairs(removal_plan) do
            local slot = game.create_inventory(1)

            local items = plan.items
            if items.in_inventory then
                for j, item in pairs(items.in_inventory) do
                    local inventory = target.get_inventory(item.inventory) --[[@as LuaInventory]]
                    if not slot[1].transfer_stack(inventory[item.stack + 1]) then -- could fail if transferring more than stack size?
                        -- slot.destroy()
                        break
                    end
                    items.in_inventory[j] = nil

                    vacuum_limit = vacuum_limit - 1
                    params.ammo_item.drain_ammo(0.125)

                    if vacuum_limit == 0 then break end
                    if not params.ammo_item.valid_for_read then break end
                end

                items.in_inventory = utils.condense(items.in_inventory)
            else
                local grid = target.grid --[[@as LuaEquipmentGrid]]
                local name = plan.id.name
                local quality = plan.id.quality or "normal"
                for _, equipment in pairs(grid.equipment) do
                    if equipment.to_be_removed and equipment.name == name and equipment.quality.name == quality then
                        if not slot[1].set_stack{name = name, count = slot[1].count + 1, quality = quality} then
                            break
                        end
                        grid.take{equipment = equipment}
                    end
                end
                items.grid_count = (items.grid_count - slot[1].count) --[[@as ItemCountType]]

                vacuum_limit = vacuum_limit - 1
                params.ammo_item.drain_ammo(0.125)

                if vacuum_limit == 0 then break end
                if not params.ammo_item.valid_for_read then break end
            end

            if not ((items.in_inventory and items.in_inventory[1]) or items.grid_count and items.grid_count > 0) then
                removal_plan[i] = nil
            end

            game.play_sound{path = "utility/picked_up_item", position = target.position}
            local sprite, shadow = render.draw_new_item(target.surface, plan.id.name --[[@as string]], target.position, 0)
            sprite.move_to_back()
            storage.vacuum_items[sprite.id] = {
                slot = slot,
                surface = params.surface,
                character = params.character,
                time = 0,
                position = target.position,
                velocity = vec.random(1/15),
                height = 0,
                orientation_deviation = utils.orientation_deviation(),
                sprite = sprite,
                shadow = shadow,
                deconstruct = params.character.force,
            }

            if vacuum_limit == 0 then break end
            if not params.ammo_item.valid_for_read then break end
        end

        proxy.removal_plan = removal_plan

        if not params.ammo_item.valid_for_read then break end

        ::continue::
    end

    return vacuum_limit < prev_limit
end