Resource_Organizer = {
    Name = "", --[[@as string]]           --In-Game Name
    Count = 0, --[[@as integer]]          --Amount of resources caught
    CountPerCell = 0, --[[@as integer]]   --Per Cell count
    Surface = "", --[[@as string]]        --Surface collected from
    Category = "", --[[@as string]]       --Resource category
    Name_Localised = "", --[[@as string]] --Localised Name
    Handler = "", --[[@as string]]        --Spread or Spaced
    Grid_Spacing = 0, --[[@as integer]]   --Spacing between special buildings
    LockSurface = true, --[[@as boolean]]
    AllowSolids = true, --[[@as boolean]]
    AllowFluids = true, --[[@as boolean]]
    AllowMixing = true --[[@as boolean]]
}

--Set Resource_Organizer settings, allowing run-time modifications
local function UpdateStoredSettings()
    Resource_Organizer.Grid_Spacing = settings.global["resource-patch-organizer-grid-spacing"].value
    Resource_Organizer.LockSurface = settings.global["resource-patch-organizer-lock-surface"].value
    Resource_Organizer.AllowSolids = settings.global["resource-patch-organizer-allow-solids"].value
    Resource_Organizer.AllowFluids = settings.global["resource-patch-organizer-allow-fluids"].value
    Resource_Organizer.AllowMixing = settings.global["resource-patch-organizer-allow-mixing"].value
end

--- @param InputString string String To Format To Camel Case
--- @return string OutputString Output of Function
local function ConvertStringToCamelCase(InputString)
    return string.gsub(" " .. InputString, "%W%l", string.upper):sub(2)
end

--- Adjusts a BoundingBox X/Y by fixed values
--- @param area BoundingBox The BoundingBox to modify
--- @param adjustX integer The value to adjust the X Coordinates
--- @param adjustY integer The value to adjust the Y Coordinates
--- @return BoundingBox area
local function AdjustBoundingBox(area, adjustX, adjustY)
    ---@type BoundingBox
    local newArea = {
        left_top = {
            x = area.left_top.x + adjustX,
            y = area.left_top.y + adjustY,
        },
        right_bottom = {
            x = area.right_bottom.x + adjustX,
            y = area.right_bottom.y + adjustY,
        },
    }
    return newArea
end

--- Round a BoundingBox outwards to increments of the snaped value i.e. select 1 tile in Chunk, and snapValue of 64 = 1 chunk selected
--- @param area BoundingBox Area to snap/round
--- @param snapValue integer bounding box divisible number to enforce
--- @param snapToEventArea? boolean True = Snap to the top left of the 'area'; False = Snap to the world grid
--- @return BoundingBox area
local function SnapArea(area, snapValue, snapToEventArea)
    ---@type integer
    local adjustX
    ---@type integer
    local adjustY
    ---@type BoundingBox
    local newArea

    ---@type integer
    local snapLimit = 1000 --Only allow region to be 'snapped' outwards by 1000

    snapValue = math.min(math.max(1, snapValue), snapLimit)

    -- 1. Round the bounding box coords to whole numbers
    newArea = {
        left_top = {
            x = math.floor(area.left_top.x),
            y = math.floor(area.left_top.y),
        },
        right_bottom = {
            x = math.ceil(area.right_bottom.x),
            y = math.ceil(area.right_bottom.y),
        },
    }
    --Get Adjust values
    if snapToEventArea == true then
        adjustX = newArea.left_top.x
        adjustY = newArea.left_top.y
    else
        adjustX = 0
        adjustY = 0
    end

    -- 2. Adjust for snapToEventArea
    -- Adjust by negative
    -- Not needed for 0,0 but included for clarity
    newArea = AdjustBoundingBox(area, -adjustX, -adjustY)

    -- 3. Snap to SnapValue
    newArea = {
        left_top = {
            x = math.floor(area.left_top.x / snapValue) * snapValue,
            y = math.floor(area.left_top.y / snapValue) * snapValue,
        },
        right_bottom = {
            x = math.ceil(area.right_bottom.x / snapValue) * snapValue,
            y = math.ceil(area.right_bottom.y / snapValue) * snapValue,
        },
    }

    -- 4. UnAdjust for snapToEventArea
    -- Adjust by positive
    -- Not needed for 0,0 but included for clarity
    newArea = AdjustBoundingBox(area, adjustX, adjustY)
    -- 5. Return
    return newArea
end

--- Returns a multiple of Height x Width
--- @param area BoundingBox
--- @return integer count
local function CountAreaTiles(area)
    local width = area.right_bottom.x - area.left_top.x
    local height = area.right_bottom.y - area.left_top.y
    return width * height
end

--- Print bounding box to ingame chat
--- @param area BoundingBox
local function PrintArea(area)
    game.print("Left Top X: " .. area.left_top.x)
    game.print("Left Top Y: " .. area.left_top.y)
    game.print("Right Bottom X: " .. area.right_bottom.x)
    game.print("Right Bottom Y: " .. area.right_bottom.y)
end

--- Validate if a BoundingBox is 0
--- @param area BoundingBox
--- @return boolean zeroSize
local function IsZeroSize(area)
    return (area.left_top.x == area.right_bottom.x and area.left_top.y == area.right_bottom.y)
end

--- Format a number into comma separated thousands
--- @param number integer Number to format into a string
--- @return string formatted_number
local function FormatInt(number)
    local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')
    -- reverse the int-string and append a comma to all blocks of 3 digits
    int = int:reverse():gsub("(%d%d%d)", "%1,")
    -- reverse the int-string back remove an optional comma and put the
    -- optional minus and fractional part back
    return minus .. int:reverse():gsub("^,", "") .. fraction
end

-- Collect Resource
function On_Player_Selected_Area(event)
    --Only handle the ore patch organiser
    if event.item == "ore-patch-organizer" then
        --Update Settings allowing Map/Per-Player modifications
        UpdateStoredSettings()

        --Skip 0 size selection
        if IsZeroSize(event.area) then return end

        --Surface Lock
        if Resource_Organizer.LockSurface then
            if event.surface.name ~= Resource_Organizer.Surface and --Different surface from previous collection
                Resource_Organizer.Surface ~= "" then               --Surface hasn't been set, new collection
                game.print({ "", "Invalid Surface. Resources were previously collected from ",
                    ConvertStringToCamelCase(Resource_Organizer.Surface) })
                return
            end
        end

        --Loop all resources in Event
                for _, resource in pairs(event.entities) do
            -- 1. Populate 'Category' with resource type (basic-solid, basic-fluid, oil, kr-quarry etc)
            --Validate Category for initial collection
            --If/Then/End to prevent excessive reuse when looping entities
            if Resource_Organizer.Category == "" then
                --Handle Solids
                if Resource_Organizer.AllowSolids then
                    if resource.prototype.resource_category == 'basic-solid' or                    --Vanilla Ores
                        resource.prototype.resource_category == 'hard-resource' or                 --K2 Hard Resource
                        resource.prototype.resource_category == 'kr-quarry' or                     --K2 Quarry
                        resource.prototype.resource_category == 'vtk-deepcore-mining-crack' or     --Vortek Deep Core Mining p.1
                        resource.prototype.resource_category == 'vtk-deepcore-mining-ore-patch' or --Vortek Deep Core Mining p.2
                        --Py Ores
                        resource.prototype.resource_category == 'antimonnium' or
                        resource.prototype.resource_category == 'basic-with-fluid' or
                        resource.prototype.resource_category == 'borax' or
                        resource.prototype.resource_category == 'molybdenum' or
                        resource.prototype.resource_category == 'niobium' or
                        resource.prototype.resource_category == 'oil-sand' or
                        resource.prototype.resource_category == 'ore-bioreserve' or
                        resource.prototype.resource_category == 'ore-nexelit' or
                        resource.prototype.resource_category == 'ore-quartz' or
                        resource.prototype.resource_category == 'phosphate' or
                        resource.prototype.resource_category == 'rare-earth' or
                        resource.prototype.resource_category == 'ree' or
                        --Py Ore Reserves
                        resource.prototype.resource_category == 'aluminium-rock' or
                        resource.prototype.resource_category == 'chromium-rock' or
                        resource.prototype.resource_category == 'coal-rock' or
                        resource.prototype.resource_category == 'copper-rock' or
                        resource.prototype.resource_category == 'iron-rock' or
                        resource.prototype.resource_category == 'nexelit-rock' or
                        resource.prototype.resource_category == 'nickel-rock' or
                        resource.prototype.resource_category == 'quartz-rock' or
                        resource.prototype.resource_category == 'regolite' or
                        resource.prototype.resource_category == 'salt-rock' or
                        resource.prototype.resource_category == 'sulfur-patch' or
                        resource.prototype.resource_category == 'tin-rock' or
                        resource.prototype.resource_category == 'titanium-rock' or
                        resource.prototype.resource_category == 'uranium-rock' or
                        resource.prototype.resource_category == 'zinc-rock' or



                        false then
                        --[[
                            TODO:
                            resource.prototype.resource_category == 'se-core-mining' or --Space Exploration Core Mining
                            skip se-core-mining due to multi-part (Fissure, Smoke, Resource)
                            Once I figure this out, allow moving of Core Miners
                        ]]

                        --Only set category if Resource is approved solid for collection
                        Resource_Organizer.Category = resource.prototype.resource_category
                    end
                end

                --Handle fluids
                if Resource_Organizer.AllowFluids then
                    if resource.prototype.resource_category == 'basic-fluid' or --Vanilla Fluid
                        resource.prototype.resource_category == 'oil' or        --K2 Oil
                        --Py Fluids
                        resource.prototype.resource_category == 'natural-gas' or
                        resource.prototype.resource_category == 'bitumen-seep' or
                        resource.prototype.resource_category == 'geothermal-crack' or
                        false then
                        --Only set category if Resource is approved fluid for collection
                        Resource_Organizer.Category = resource.prototype.resource_category
                    end
                end
            end

            -- Contain remaining validation within Category If/Then/End, to prevent extra checks that don't need to be done
            --Category = "" - Do nothing, not valid collection
            --Category != "" - Collect resources/validate
            if Resource_Organizer.Category ~= "" then
                -- 2. Populate Handler as Spaced|Spread (Oil is Spaced out, Ores are spread etc)
                if Resource_Organizer.Handler == "" then
                    --Set if resource is Spaced (Oil patches/some modded types) or Spread (Raw Ores)
                    if Resource_Organizer.Category == 'basic-solid' or
                        Resource_Organizer.Category == 'hard-resource' or
                        --Py Ores
                        Resource_Organizer.Category == 'antimonnium' or
                        Resource_Organizer.Category == 'basic-with-fluid' or
                        Resource_Organizer.Category == 'borax' or
                        Resource_Organizer.Category == 'molybdenum' or
                        Resource_Organizer.Category == 'niobium' or
                        Resource_Organizer.Category == 'oil-sand' or
                        Resource_Organizer.Category == 'ore-bioreserve' or
                        Resource_Organizer.Category == 'ore-nexelit' or
                        Resource_Organizer.Category == 'ore-quartz' or
                        Resource_Organizer.Category == 'phosphate' or
                        Resource_Organizer.Category == 'rare-earth' or
                        Resource_Organizer.Category == 'ree' or
                        false then
                        Resource_Organizer.Handler = 'spread'
                    elseif Resource_Organizer.Category == 'basic-fluid' or
                        Resource_Organizer.Category == 'oil' or
                        Resource_Organizer.Category == 'se-core-mining' or
                        Resource_Organizer.Category == 'vtk-deepcore-mining-crack' or
                        Resource_Organizer.Category == 'vtk-deepcore-mining-ore-patch' or
                        Resource_Organizer.Category == 'kr-quarry' or
                        --Py Ore Rocks
                        Resource_Organizer.Category == 'aluminium-rock' or
                        Resource_Organizer.Category == 'chromium-rock' or
                        Resource_Organizer.Category == 'coal-rock' or
                        Resource_Organizer.Category == 'copper-rock' or
                        Resource_Organizer.Category == 'iron-rock' or
                        Resource_Organizer.Category == 'nexelit-rock' or
                        Resource_Organizer.Category == 'nickel-rock' or
                        Resource_Organizer.Category == 'quartz-rock' or
                        Resource_Organizer.Category == 'regolite' or
                        Resource_Organizer.Category == 'salt-rock' or
                        Resource_Organizer.Category == 'sulfur-patch' or
                        Resource_Organizer.Category == 'tin-rock' or
                        Resource_Organizer.Category == 'titanium-rock' or
                        Resource_Organizer.Category == 'uranium-rock' or
                        Resource_Organizer.Category == 'zinc-rock' or
                        --Py Fluids
                        Resource_Organizer.Category == 'natural-gas' or
                        Resource_Organizer.Category == 'bitumen-seep' or
                        Resource_Organizer.Category == 'geothermal-crack' or

                        
                        false then
                        Resource_Organizer.Handler = 'spaced'
                    end
                end

                -- 3. Populate Name,Category,Surface
                if Resource_Organizer.Name == "" or
                    Resource_Organizer.Name_Localised == "" or
                    Resource_Organizer.Surface == "" then
                    --1. Base Name
                    if Resource_Organizer.Name == "" then
                        Resource_Organizer.Name = resource.name
                    end
                    --2. Localised Name
                    if Resource_Organizer.Name_Localised == "" then
                        Resource_Organizer.Name_Localised = resource.localised_name
                    end

                    --3. Surface
                    if Resource_Organizer.Surface == "" then
                        Resource_Organizer.Surface = event.surface.name
                    end
                end
            end
            -- At this point all validation and variables are set

            -- Resource found must match Name
            if resource.name == Resource_Organizer.Name then
                Resource_Organizer.Count = Resource_Organizer.Count + resource.amount
                resource.destroy()
            end
        end

        --Show the user what we've collected
        game.print({ "", "Total ", Resource_Organizer.Name_Localised, " Captured: ", FormatInt(Resource_Organizer.Count) })
    end
end

-- Print Resource
function On_Player_Alt_Selected_Area(event)
    -- Only ore patch organizer
    if event.item == "ore-patch-organizer" then
        --Update Settings allowing Map/Per-Player modifications
        UpdateStoredSettings()

        -- No area selected
        if IsZeroSize(event.area) then return end

        -- No resources previously collected
        if Resource_Organizer.Name == "" or Resource_Organizer.count == 0 then return end

        -- Different surface from previous collection
        if Resource_Organizer.LockSurface and event.surface.name ~= Resource_Organizer.Surface then
            game.print({ "", "Invalid Surface. Resources were previously collected from ",
                ConvertStringToCamelCase(Resource_Organizer.Surface) })
            return
        end

        -- Other resources are in the way - Check setting
        if not Resource_Organizer.AllowMixing then
            for _, resource in pairs(event.entities) do
                if resource.type == "resource" then
                    game.print({ "", "Cannot print ", Resource_Organizer.Name_Localised,
                        ". Other Resources are in the way" })
                    return
                end
            end
        end

        --Count valid and invalid tiles in area
        local validCells = 0
        local invalidCells = 0
        for x = event.area.left_top.x, event.area.right_bottom.x do     --iterate x axis
            for y = event.area.left_top.y, event.area.right_bottom.y do --iterate y axis
                if event.surface.can_place_entity { name = Resource_Organizer.Name, position = { x, y } } then
                    validCells = validCells + 1
                else
                    invalidCells = invalidCells + 1
                end
            end
        end

        --There's got to be some cells to print to
        if validCells == 0 then
            game.print({ "", "No valid tiles selected to print ", FormatInt(Resource_Organizer.Count), " ",
                Resource_Organizer.Name_Localised })
            return
        end

        --No area, don't say we're "Printing"
        if Resource_Organizer.Handler == 'spaced' and invalidCells ~= 0 then
            --Spaced Resources must be placed on fully empty ground
            --This is for pure laziness to prevent calculating collisions
            game.print({ "", "Fluids must have fully empty ground. Can't print ", FormatInt(Resource_Organizer
                .Count),
                " ", Resource_Organizer.Name_Localised })
            return
        end

        --If we get here, there are no resources in the area, there is space to print
        --Ensure at leaste 1 ore per tile. Round up to prevent remainder ores
        Resource_Organizer.CountPerCell = math.max(math.ceil(Resource_Organizer.Count / validCells), 1)
        game.print({ "", "Printing ", Resource_Organizer.Name_Localised, ": ", FormatInt(Resource_Organizer.Count) })

        if Resource_Organizer.Handler == 'spread' then
            --Print solids in a clean square
            for x = event.area.left_top.x, event.area.right_bottom.x do     --Iterate x axis
                for y = event.area.left_top.y, event.area.right_bottom.y do --iterate y axis
                    -- Check resources to print, and not colliding
                    if Resource_Organizer.Count ~= 0 and event.surface.can_place_entity { name = Resource_Organizer.Name, position = { x, y } } then
                        --Print resource
                        event.surface.create_entity({
                            name = Resource_Organizer.Name,
                            position = { x, y },
                            amount = math.min(Resource_Organizer.Count, Resource_Organizer.CountPerCell)
                        })
                        --Remove printed resource from our total count
                        Resource_Organizer.Count = Resource_Organizer.Count -
                            math.min(Resource_Organizer.Count, Resource_Organizer.CountPerCell)
                    end
                end
            end
            --Reset Mining Drills to detect any new ores pasted
            for _, e in pairs(event.surface.find_entities_filtered { area = event.area, type = "mining-drill" }) do
                e.update_connections()
            end
        elseif Resource_Organizer.Handler == 'spaced' then
            --Print fluids in an even grid
            local tileGrid = 0 --[[@as integer]]
            local machineSize = 0 --[[@as integer]]
            if Resource_Organizer.Category == 'basic-fluid' then
                --Default fluid types Pumpjacks are 3x3
                machineSize = 3
            elseif Resource_Organizer.Category == 'oil' then
                --K2 Oil Pumpjacks are 3x3
                machineSize = 3
            elseif Resource_Organizer.Category == 'se-core-mining' then
                --Core miner is 11x11
                machineSize = 11
            elseif Resource_Organizer.Category == 'kr-quarry' then
                --Quarry Drill is 7x7
                machineSize = 7
            elseif Resource_Organizer.Category == 'vtk-deepcore-mining-crack' then
                --Vortek Deep Core Mining Drill is 9x9
                machineSize = 9
            elseif Resource_Organizer.Category == 'vtk-deepcore-mining-ore-patch' then
                --Vortek Moho Mining Drill is 5x5
                machineSize = 5
            end
            tileGrid = Resource_Organizer.Grid_Spacing + machineSize

            local newArea = SnapArea(event.area, 1)
            --math.ceil to 'include' the bottom right tile in the selection, otherwise math.floor excludes it requiring the player to select beyond the area

            --100 tiles with tileGrid of 6 (3 for Pumpjack, 3 for Spacing) = 16.66, Rounded down to 16
            --i.e. 100x100 = 16x16 grid of fluid placement options = 96x96 used space
            local totalX = math.floor((event.area.right_bottom.x - event.area.left_top.x + machineSize) / tileGrid)
            local totalY = math.floor((event.area.right_bottom.y - event.area.left_top.y + machineSize) / tileGrid)


            if totalX <= 0 or totalY <= 0 then
                --Area too small - Print Single instance
                event.surface.create_entity({
                    name = Resource_Organizer.Name,
                    amount = Resource_Organizer.Count,
                    position = { event.area.left_top.x, event.area.left_top.y }
                })
            else
                Resource_Organizer.CountPerCell = math.max(math.ceil(Resource_Organizer.Count / (totalX * totalY)), 1)


                --Iterate via int Variables instead of direct Event X/Y because of rounding and causing an extra instance placing
                --Iterate x axis
                for x = 0, (totalX - 1) do
                    --Iterate y axis
                    for y = 0, (totalY - 1) do
                        --Print Fluids
                        event.surface.create_entity({
                            name = Resource_Organizer.Name,
                            amount = math.min(Resource_Organizer.Count, Resource_Organizer.CountPerCell),
                            position = { event.area.left_top.x + (x * tileGrid),
                                event.area.left_top.y + (y * tileGrid) }
                        })
                        Resource_Organizer.Count = Resource_Organizer.Count -
                            math.min(Resource_Organizer.Count, Resource_Organizer.CountPerCell)
                    end
                end
            end
        end

        --Finish by removing the existing details
        Resource_Organizer.Name = ""
        Resource_Organizer.Count = 0
        Resource_Organizer.CountPerCell = 0
        Resource_Organizer.Surface = ""
        Resource_Organizer.Category = ""
        Resource_Organizer.Name_Localised = ""
        Resource_Organizer.Handler = ""
    end
end
