data:extend{
    {
        type = "gun",
        name = "blueprint-shotgun",
        icon = "__blueprint-shotgun__/graphics/blueprint-shotgun.png",
        icon_size = 64,
        stack_size = 1,
        attack_parameters = {
            type = "projectile",
            cooldown = 1,
            range = 15,
            movement_slow_down_factor = 0,
            ammo_consumption_modifier = 0,
            ammo_categories = {"blueprint-ammo"},
        },
        subgroup = "gun",
        order = "a[a-blueprint-shotgun]",
    } --[[@as data.GunPrototype]],
    {
        type = "ammo",
        name = "item-canister",
        icon = "__blueprint-shotgun__/graphics/item-canister.png",
        icon_size = 64,
        stack_size = 200,
        magazine_size = 25,
        ammo_type = {
            category = "blueprint-ammo",
            target_type = "position",
            action = {
                type = "direct",
                action_delivery = {
                    type = "instant",
                    target_effects = {
                        type = "script",
                        effect_id = "blueprint-shotgun",
                    },
                },
            },
        },
        subgroup = "ammo",
        order = "a[a-blueprint-shotgun]",
    } --[[@as data.AmmoItemPrototype]],
    {
        type = "ammo-category",
        name = "blueprint-ammo",
    } --[[@as data.AmmoCategory]],
    {
        type = "recipe",
        name = "blueprint-shotgun",
        energy_required = 10,
        results = {{type = "item", name = "blueprint-shotgun", amount = 1}},
        ingredients = {
            {type = "item", name = "shotgun", amount = 1},
            {type = "item", name = "electronic-circuit", amount = 5},
            {type = "item", name = "iron-gear-wheel", amount = 10},
        },
        enabled = false,
        subgroup = "gun",
        -- order = "b[blueprint-shotgun]",
    } --[[@as data.RecipePrototype]],
    {
        type = "recipe",
        name = "item-canister",
        results = {{type = "item", name = "item-canister", amount = 1}},
        ingredients = {
            {type = "item", name = "iron-plate", amount = 1},
            {type = "item", name = "copper-plate", amount = 2},
            {type = "item", name = "iron-stick", amount = 3},
        },
        enabled = false,
        subgroup = "ammo",
        -- order = "b[blueprint-shotgun]",
    } --[[@as data.RecipePrototype]],
    {
        type = "technology",
        name = "blueprint-shotgun",
        icon = "__blueprint-shotgun__/graphics/blueprint-shotgun.png",
        icon_size = 64,
        effects = {{
            type = "unlock-recipe",
            recipe = "blueprint-shotgun",
        }, {
            type = "unlock-recipe",
            recipe = "item-canister",
        }},
        unit = {
            count = 50,
            ingredients = {
                {type = "item", name = "automation-science-pack", amount = 1},
            },
            time = 30,
        },
        prerequisites = {"military"},
    } --[[@as data.TechnologyPrototype]],
    {
        type = "sound",
        name = "blueprint-shotgun-shoot",
        category = "game-effect",
        filename = "__blueprint-shotgun__/sounds/shoot.ogg",
        min_speed = 0.95,
        max_speed = 1.05,
        game_controller_vibration_data =
        {
            high_frequency_vibration_intensity = 0.6,
            duration = 100,
        },
    } --[[@as data.SoundPrototype]],
    {
        type = "sound",
        name = "blueprint-shotgun-vacuum-start",
        category = "game-effect",
        filename = "__blueprint-shotgun__/sounds/vacuum-start.ogg",
        game_controller_vibration_data = {
            high_frequency_vibration_intensity = 0.6,
            duration = 100,
        }
    } --[[@as data.SoundPrototype]],
    {
        type = "sprite",
        name = "item-shadow",
        filename = "__blueprint-shotgun__/graphics/item-shadow.png",
        size = 16,
        draw_as_shadow = true,
    } --[[@as data.SpritePrototype]],
    {
        type = "projectile",
        name = "vacuum-smoke",
        flags = {"not-on-map", "placeable-off-grid"},
        acceleration = 0.01,
        animation = {
            filename = "__blueprint-shotgun__/graphics/vacuum-smoke.png",
            -- draw_as_glow = true,
            frame_count = 16,
            width = 50,
            height = 50,
            priority = "high",
        }
    } --[[@as data.ProjectilePrototype]],
    {
        type = "custom-input",
        name = "blueprint-shotgun-shoot",
        key_sequence = "",
        linked_game_control = "shoot-enemy"
    } --[[@as data.CustomInputPrototype]],
    {
        type = "custom-input",
        name = "blueprint-shotgun-mode-swap",
        key_sequence = "CONTROL + TAB",
    } --[[@as data.CustomInputPrototype]],
}

for i = 1, 2 do
    local ingredients = {{type = "item", name = "automation-science-pack", amount = 1}}
    local prerequisites = i == 1 and {"blueprint-shotgun"} or {"blueprint-shotgun-upgrade-1", "logistic-science-pack"}
    if i == 2 then
        ingredients[2] = {type = "item", name = "logistic-science-pack", amount = 1}
    end

    data:extend{{
        type = "technology",
        name = "blueprint-shotgun-upgrade-" .. i,
        icon = "__blueprint-shotgun__/graphics/blueprint-shotgun.png",
        icon_size = 64,
        effects = {{
            type = "nothing",
            effect_description = {"blueprint-shotgun.capacity-upgrade"}
        }, {
            type = "nothing",
            effect_description = {"blueprint-shotgun.vacuum-upgrade"}
        }},
        unit = {
            count = i * 100,
            ingredients = ingredients,
            time = 30,
        },
        prerequisites = prerequisites,
        upgrade = true,
        localised_name = {"technology-name.blueprint-shotgun-upgrade", i},
        localised_description = {"technology-description.blueprint-shotgun-upgrade"},
    }} --[=[@as data.TechnologyPrototype[]]=]
end

for i = 1, 160 do
    data:extend{{
        type = "sound",
        name = "blueprint-shotgun-vacuum-" .. i,
        category = "game-effect",
        filename = "__blueprint-shotgun__/sounds/vacuum/vacuum-" .. i .. ".ogg",
        game_controller_vibration_data = {
            low_frequency_vibration_intensity = 0.4,
            duration = 100,
        }
    }}
end

data:extend{{
    type = "character",
    name = "blueprint-shotgun-character",
    icon = "__core__/graphics/icons/entity/character.png",
    icon_size = 64, icon_mipmaps = 4,
    flags = {"placeable-off-grid", "not-repairable", "not-on-map", "not-flammable", "not-selectable-in-game"},
    animations = {{
        idle = util.empty_sprite(),
        idle_with_gun = util.empty_sprite(),
        running = util.empty_sprite(),
        running_with_gun = {
            direction_count = 18,
            filename = "__blueprint-shotgun__/graphics/running-with-gun.png",
            size = 1,
        },
        mining_with_tool = util.empty_sprite(),
    }},
    build_distance = 0,
    damage_hit_tint = {},
    distance_per_frame = 0,
    drop_item_distance = 0,
    eat = {filename = "__core__/sound/silence-1sec.ogg", volume = 0},
    heartbeat = {filename = "__core__/sound/silence-1sec.ogg", volume = 0},
    inventory_size = 100,
    item_pickup_distance = 0,
    loot_pickup_distance = 0,
    maximum_corner_sliding_distance = 0,
    mining_speed = 0,
    mining_with_tool_particles_animation_positions = {0},
    reach_distance = 0,
    reach_resource_distance = 0,
    running_sound_animation_positions = {0},
    running_speed = 0,
    ticks_to_keep_aiming_direction = 0,
    ticks_to_keep_gun = 0,
    ticks_to_stay_in_combat = 0,
} --[[@as data.CharacterPrototype]]}