local lib = {}

function lib.on_tick(event)
    if event.tick % 3 ~= 0 then return end

    for _, data in pairs(global.characters) do
        local character = data.character
        if not character.valid then goto continue end

        if event.tick - data.tick <= 3 then
            if data.volume == 0 then
                if data.mode ~= "mine" then goto continue end
                character.surface.play_sound{path = "blueprint-shotgun-vacuum-start", volume_modifier = 0.25, position = character.position}
            end
            data.volume = math.min(1, data.volume + 1/5)
        else
            data.volume = math.max(0, data.volume - 1/10)
        end
        if data.volume == 0 then goto continue end

        local sound_index = math.floor(event.tick / 3 - 1) % 160 + 1
        character.surface.play_sound{
            path = "blueprint-shotgun-vacuum-" .. sound_index,
            volume_modifier = data.volume * 0.75,
            position = character.position
        }

        ::continue::
    end
end

return lib